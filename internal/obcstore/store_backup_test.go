package obcstore

import (
	"bytes"
	"encoding/base64"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestStoreDataDirBackupRestore(t *testing.T) {
	dataDir := t.TempDir()
	svc, err := New(Config{
		DataDir:       dataDir,
		AdminUser:     "admin",
		AdminPassword: "secret",
		Now: func() time.Time {
			return time.Date(2026, 6, 4, 0, 0, 0, 0, time.UTC)
		},
	})
	if err != nil {
		t.Fatal(err)
	}
	ts := httptest.NewServer(svc.Handler())
	defer ts.Close()

	program := []byte{0xcd, 0x0e, 0x00, 0x01}
	bundle := testBundleZip(t, map[string][]byte{
		"package.json": []byte(`{"schema":"oren.obc.package.v0","capabilities":["CORE"]}`),
		"program.obc":  program,
	})
	asset := []byte("restore-asset-ok")
	if got := request(t, ts, http.MethodPost, "/api/v0/publishers", map[string]any{"id": "oren-labs"}, true); got.Code != http.StatusCreated {
		t.Fatalf("publisher status=%d body=%s", got.Code, got.Body.String())
	}
	if got := request(t, ts, http.MethodPost, "/api/v0/packages", map[string]any{"publisher": "oren-labs", "name": "restore-demo"}, true); got.Code != http.StatusCreated {
		t.Fatalf("package status=%d body=%s", got.Code, got.Body.String())
	}
	upload := map[string]any{
		"version":               "0.1.0",
		"program_obc_base64":    base64.StdEncoding.EncodeToString(program),
		"release_bundle_base64": base64.StdEncoding.EncodeToString(bundle),
		"manifest":              map[string]any{"capabilities": []string{"CORE"}},
		"assets": []map[string]any{
			{
				"path":           "assets/readme.txt",
				"media_type":     "text/plain",
				"content_base64": base64.StdEncoding.EncodeToString(asset),
			},
		},
	}
	if got := request(t, ts, http.MethodPost, "/api/v0/packages/oren-labs/restore-demo/versions", upload, true); got.Code != http.StatusCreated {
		t.Fatalf("version status=%d body=%s", got.Code, got.Body.String())
	}
	if got := request(t, ts, http.MethodPost, "/api/v0/packages/oren-labs/restore-demo/versions/0.1.0/publish", map[string]any{}, true); got.Code != http.StatusOK {
		t.Fatalf("publish status=%d body=%s", got.Code, got.Body.String())
	}

	backupDir := filepath.Join(t.TempDir(), "obc-store-backup")
	if err := copyDir(dataDir, backupDir); err != nil {
		t.Fatalf("copy backup: %v", err)
	}
	restoredSvc, err := New(Config{
		DataDir:       backupDir,
		AdminUser:     "admin",
		AdminPassword: "secret",
	})
	if err != nil {
		t.Fatal(err)
	}
	restored := httptest.NewServer(restoredSvc.Handler())
	defer restored.Close()

	index := getJSON[map[string]any](t, restored, "/api/v0/index.json")
	packages := index["packages"].([]any)
	if len(packages) != 1 {
		t.Fatalf("restored index packages=%v", packages)
	}
	if !strings.Contains(string(rawGet(t, restored, "/packages/oren-labs/restore-demo")), "restore-demo") {
		t.Fatalf("restored browser page missing package")
	}
	if got := rawGet(t, restored, "/api/v0/packages/oren-labs/restore-demo/versions/0.1.0/program.obc"); !bytes.Equal(got, program) {
		t.Fatalf("restored program bytes=%x", got)
	}
	if got := rawGet(t, restored, "/api/v0/packages/oren-labs/restore-demo/versions/0.1.0/bundle.obc.zip"); !bytes.Equal(got, bundle) {
		t.Fatalf("restored bundle len=%d want=%d", len(got), len(bundle))
	}
	if got := rawGet(t, restored, "/api/v0/packages/oren-labs/restore-demo/versions/0.1.0/assets/readme.txt"); !bytes.Equal(got, asset) {
		t.Fatalf("restored asset=%q", string(got))
	}
	statusResp := request(t, restored, http.MethodGet, "/api/v0/ops/status", nil, true)
	if statusResp.Code != http.StatusOK {
		t.Fatalf("restored ops status=%d body=%s", statusResp.Code, statusResp.Body.String())
	}
	var status map[string]any
	if err := json.Unmarshal(statusResp.Body.Bytes(), &status); err != nil {
		t.Fatalf("decode restored ops status: %v body=%s", err, statusResp.Body.String())
	}
	if status["published_release_count"] != float64(1) || status["bundle_release_count"] != float64(1) || status["data_dir_writable"] != true || status["data_dir_bytes"].(float64) <= 0 || status["payload_bytes"].(float64) <= 0 {
		t.Fatalf("restored status=%v", status)
	}
}

func copyDir(src, dst string) error {
	return filepath.WalkDir(src, func(path string, entry os.DirEntry, err error) error {
		if err != nil {
			return err
		}
		rel, err := filepath.Rel(src, path)
		if err != nil {
			return err
		}
		if rel == "." {
			return os.MkdirAll(dst, 0o755)
		}
		target := filepath.Join(dst, rel)
		if entry.IsDir() {
			return os.MkdirAll(target, 0o755)
		}
		info, err := entry.Info()
		if err != nil {
			return err
		}
		if info.Mode()&os.ModeType != 0 {
			return nil
		}
		body, err := os.ReadFile(path)
		if err != nil {
			return err
		}
		return os.WriteFile(target, body, info.Mode().Perm())
	})
}
