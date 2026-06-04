package obcstore

import (
	"archive/zip"
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
)

func decodeJSON(w http.ResponseWriter, r *http.Request, dst any) bool {
	defer r.Body.Close()
	dec := json.NewDecoder(io.LimitReader(r.Body, 32<<20))
	dec.DisallowUnknownFields()
	if err := dec.Decode(dst); err != nil {
		http.Error(w, "invalid JSON: "+err.Error(), http.StatusBadRequest)
		return false
	}
	return true
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

func writeJSONFile(path string, v any) error {
	body, err := marshalJSON(v)
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	return os.WriteFile(path, body, 0o644)
}

func readJSONFile[T any](path string) (T, error) {
	var out T
	body, err := os.ReadFile(path)
	if err != nil {
		return out, err
	}
	err = json.Unmarshal(body, &out)
	return out, err
}

func fileExists(path string) bool {
	st, err := os.Stat(path)
	return err == nil && !st.IsDir()
}

func marshalJSON(v any) ([]byte, error) {
	body, err := json.MarshalIndent(v, "", "  ")
	if err != nil {
		return nil, err
	}
	return append(body, '\n'), nil
}

func validateManifestPermissionDefaults(manifest map[string]any) error {
	if manifest == nil {
		return nil
	}
	raw, ok := manifest["permission_defaults"]
	if !ok || raw == nil {
		return nil
	}
	defaults, ok := raw.([]any)
	if !ok {
		return errors.New("must be an array")
	}
	for i, item := range defaults {
		entry, ok := item.(map[string]any)
		if !ok {
			return fmt.Errorf("entry %d must be an object", i)
		}
		domain, ok := entry["domain"].(string)
		if !ok || domain == "" {
			return fmt.Errorf("entry %d requires non-empty string domain", i)
		}
		action, ok := entry["action"].(string)
		if !ok || action == "" {
			return fmt.Errorf("entry %d requires non-empty string action", i)
		}
		if detail, ok := entry["detail"]; ok && detail != nil {
			if _, ok := detail.(string); !ok {
				return fmt.Errorf("entry %d detail must be a string", i)
			}
		}
		if granted, ok := entry["granted"]; ok && granted != nil {
			if _, ok := granted.(bool); !ok {
				return fmt.Errorf("entry %d granted must be boolean", i)
			}
		}
	}
	return nil
}

func sha256Hex(body []byte) string {
	sum := sha256.Sum256(body)
	return hex.EncodeToString(sum[:])
}

func decodeHex(raw string) []byte {
	if raw == "" || len(raw)%2 != 0 {
		return nil
	}
	body, err := hex.DecodeString(raw)
	if err != nil {
		return nil
	}
	return body
}

func validSHA256Hex(raw string) bool {
	body, err := hex.DecodeString(strings.TrimSpace(raw))
	return err == nil && len(body) == sha256.Size
}

func safeID(s string) bool {
	if s == "" || len(s) > 80 {
		return false
	}
	for _, r := range s {
		if (r >= 'a' && r <= 'z') || (r >= '0' && r <= '9') || r == '-' || r == '_' {
			continue
		}
		return false
	}
	return true
}

func safeVersion(s string) bool {
	if s == "" || len(s) > 80 {
		return false
	}
	for _, r := range s {
		if (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') || (r >= '0' && r <= '9') || strings.ContainsRune(".-_+", r) {
			continue
		}
		return false
	}
	return true
}

func safeRelPath(p string) bool {
	if p == "" || strings.HasPrefix(p, "/") || strings.Contains(p, "\\") {
		return false
	}
	clean := filepath.ToSlash(filepath.Clean(filepath.FromSlash(p)))
	return clean == p && clean != "." && !strings.HasPrefix(clean, "../") && !strings.Contains(clean, "/../")
}

func validateReleaseBundleZIP(body []byte) error {
	if len(body) == 0 {
		return errors.New("empty bundle")
	}
	reader, err := zip.NewReader(bytes.NewReader(body), int64(len(body)))
	if err != nil {
		return err
	}
	seenManifest := false
	seenProgram := false
	for _, file := range reader.File {
		name := filepath.ToSlash(file.Name)
		if strings.HasSuffix(name, "/") {
			dirName := strings.TrimSuffix(name, "/")
			if !safeRelPath(dirName) {
				return fmt.Errorf("unsafe path %q", file.Name)
			}
			continue
		}
		if !safeRelPath(name) {
			return fmt.Errorf("unsafe path %q", file.Name)
		}
		if file.FileInfo().Mode()&os.ModeSymlink != 0 {
			return fmt.Errorf("symlink path %q", file.Name)
		}
		switch name {
		case "package.json":
			seenManifest = true
		case "program.obc":
			seenProgram = true
		}
	}
	if !seenManifest || !seenProgram {
		return errors.New("bundle must contain package.json and program.obc")
	}
	return nil
}

func parseLimit(raw string, def int) int {
	if raw == "" {
		return def
	}
	n, err := strconv.Atoi(raw)
	if err != nil || n <= 0 {
		return def
	}
	if n > 200 {
		return 200
	}
	return n
}

func containsLower(items []string, want string) bool {
	for _, item := range items {
		if strings.ToLower(item) == want {
			return true
		}
	}
	return false
}

func containsString(items []string, want string) bool {
	for _, item := range items {
		if item == want {
			return true
		}
	}
	return false
}

func releaseManifestDeclaresAsset(dir, path string) bool {
	body, err := os.ReadFile(filepath.Join(dir, "package.json"))
	if err != nil {
		return false
	}
	var manifest map[string]any
	if json.Unmarshal(body, &manifest) != nil {
		return false
	}
	assets, _ := manifest["assets"].([]any)
	for _, raw := range assets {
		asset, ok := raw.(map[string]any)
		if !ok {
			continue
		}
		if fmt.Sprint(asset["path"]) == path {
			return true
		}
	}
	return false
}

func manifestHasCapability(dir, want string) bool {
	body, err := os.ReadFile(filepath.Join(dir, "package.json"))
	if err != nil {
		return false
	}
	var m map[string]any
	if json.Unmarshal(body, &m) != nil {
		return false
	}
	caps, _ := m["capabilities"].([]any)
	for _, cap := range caps {
		if strings.ToLower(fmt.Sprint(cap)) == want {
			return true
		}
	}
	return false
}
