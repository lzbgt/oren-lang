package obcstore

import (
	"archive/zip"
	"bytes"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"encoding/pem"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"testing"
	"time"
)

func TestStorePublishSearchDownloadAndYank(t *testing.T) {
	svc, err := New(Config{
		DataDir:       t.TempDir(),
		AdminUser:     "admin",
		AdminPassword: "secret",
		Now: func() time.Time {
			return time.Date(2026, 6, 1, 0, 0, 0, 0, time.UTC)
		},
	})
	if err != nil {
		t.Fatal(err)
	}
	ts := httptest.NewServer(svc.Handler())
	defer ts.Close()

	if got := request(t, ts, http.MethodGet, "/api/v0/health", nil, false); got.Code != http.StatusOK {
		t.Fatalf("health status=%d body=%s", got.Code, got.Body.String())
	}
	if got := request(t, ts, http.MethodGet, "/healthz", nil, false); got.Code != http.StatusOK {
		t.Fatalf("healthz status=%d body=%s", got.Code, got.Body.String())
	}
	if got := request(t, ts, http.MethodPost, "/healthz", nil, false); got.Code != http.StatusMethodNotAllowed {
		t.Fatalf("healthz post status=%d body=%s", got.Code, got.Body.String())
	}
	if got := request(t, ts, http.MethodPost, "/api/v0/publishers", map[string]any{"id": "oren-labs"}, false); got.Code != http.StatusUnauthorized {
		t.Fatalf("unauthorized publisher status=%d", got.Code)
	}
	if got := request(t, ts, http.MethodPost, "/api/v0/publishers", map[string]any{"id": "oren-labs", "display_name": "Oren Labs"}, true); got.Code != http.StatusCreated {
		t.Fatalf("publisher status=%d body=%s", got.Code, got.Body.String())
	}
	previewPNG := []byte{0x89, 'P', 'N', 'G', '\r', '\n', 0x1a, '\n'}
	sourceOren := "import math \"std:math\"\n\nfn main() {\n    print(\"demo\")\n}\n\nmain()\n"
	pkg := map[string]any{
		"publisher": "oren-labs",
		"name":      "plot-demo",
		"title":     "Plot Demo",
		"summary":   "Interactive plot",
		"tags":      []string{"science", "plot"},
	}
	if got := request(t, ts, http.MethodPost, "/api/v0/packages", pkg, true); got.Code != http.StatusCreated {
		t.Fatalf("package status=%d body=%s", got.Code, got.Body.String())
	}
	badUpload := map[string]any{
		"version":            "0.0.1",
		"program_obc_base64": base64.StdEncoding.EncodeToString([]byte{0xcd, 0x0e, 0x00, 0x01}),
		"manifest": map[string]any{
			"permission_defaults": []any{
				map[string]any{"domain": "NET", "action": "connect", "detail": 443},
			},
		},
	}
	if got := request(t, ts, http.MethodPost, "/api/v0/packages/oren-labs/plot-demo/versions", badUpload, true); got.Code != http.StatusBadRequest {
		t.Fatalf("bad permission_defaults status=%d body=%s", got.Code, got.Body.String())
	}
	upload := map[string]any{
		"version":               "0.1.0",
		"program_obc_base64":    base64.StdEncoding.EncodeToString([]byte{0xcd, 0x0e, 0x00, 0x01}),
		"release_bundle_base64": base64.StdEncoding.EncodeToString(testBundleZip(t, map[string][]byte{"package.json": []byte(`{"schema":"oren.obc.package.v0"}`), "program.obc": []byte{0xcd, 0x0e, 0x00, 0x01}, "assets/source/main.oren": []byte(sourceOren)})),
		"tags":                  []string{"science", "gfx"},
		"min_app":               "0.1.0",
		"manifest": map[string]any{
			"title":        "Plot Demo",
			"summary":      "Interactive plot",
			"capabilities": []string{"CORE", "GFX", "NET"},
			"sources": []map[string]any{
				{"path": "assets/source/main.oren", "language": "oren", "role": "main"},
			},
			"permission_defaults": []any{
				map[string]any{"domain": "NET", "action": "connect", "detail": "https://api.example.invalid", "granted": false, "reason": "optional sync"},
			},
		},
		"assets": []map[string]any{
			{
				"path":           "assets/source/main.oren",
				"media_type":     "text/x-oren",
				"content_base64": base64.StdEncoding.EncodeToString([]byte(sourceOren)),
			},
			{
				"path":           "assets/readme.txt",
				"media_type":     "text/plain",
				"content_base64": base64.StdEncoding.EncodeToString([]byte("asset-ok")),
			},
		},
		"screenshots": []map[string]any{
			{
				"path":           "preview.png",
				"media_type":     "image/png",
				"content_base64": base64.StdEncoding.EncodeToString(previewPNG),
			},
		},
	}
	if got := request(t, ts, http.MethodPost, "/api/v0/packages/oren-labs/plot-demo/versions", upload, true); got.Code != http.StatusCreated {
		t.Fatalf("version status=%d body=%s", got.Code, got.Body.String())
	}
	if got := request(t, ts, http.MethodPost, "/api/v0/packages/oren-labs/plot-demo/versions/0.1.0/publish", map[string]any{}, true); got.Code != http.StatusOK {
		t.Fatalf("publish status=%d body=%s", got.Code, got.Body.String())
	}

	index := getJSON[map[string]any](t, ts, "/api/v0/index.json")
	packages, ok := index["packages"].([]any)
	if !ok || len(packages) != 1 {
		t.Fatalf("index packages=%v", index["packages"])
	}
	entry := packages[0].(map[string]any)
	if entry["id"] != "oren-labs/plot-demo" || entry["version"] != "0.1.0" {
		t.Fatalf("bad index entry=%v", entry)
	}
	manifestPath := entry["manifest"].(string)
	if !strings.HasSuffix(manifestPath, "/package.json") {
		t.Fatalf("bad manifest path=%q", manifestPath)
	}
	if entry["bundle_media_type"] != releaseBundleMediaType || !strings.HasSuffix(entry["bundle"].(string), "/bundle.obc.zip") {
		t.Fatalf("bad bundle index entry=%v", entry)
	}
	manifest := getJSON[map[string]any](t, ts, "/api/v0/packages/oren-labs/plot-demo/versions/0.1.0/package.json")
	defaults := manifest["permission_defaults"].([]any)
	if len(defaults) != 1 {
		t.Fatalf("permission_defaults=%v", defaults)
	}
	perm := defaults[0].(map[string]any)
	if perm["domain"] != "NET" || perm["action"] != "connect" || perm["detail"] != "https://api.example.invalid" || perm["granted"] != false {
		t.Fatalf("bad permission default=%v", perm)
	}
	for _, raw := range manifest["assets"].([]any) {
		asset := raw.(map[string]any)
		if strings.HasPrefix(asset["path"].(string), "screenshots/") || asset["role"] == "screenshot" {
			t.Fatalf("screenshot leaked into package manifest assets: %v", asset)
		}
	}

	home := string(rawGet(t, ts, "/"))
	if !strings.Contains(home, "Plot Demo") || !strings.Contains(home, "/packages/oren-labs/plot-demo") || !strings.Contains(home, "/publishers/oren-labs") {
		t.Fatalf("home page missing package: %s", home)
	}
	if !strings.Contains(home, `<img class="preview"`) || !strings.Contains(home, "/screenshots/preview.png") {
		t.Fatalf("home page missing screenshot: %s", home)
	}
	detail := string(rawGet(t, ts, "/packages/oren-labs/plot-demo"))
	if !strings.Contains(detail, "program.obc") || !strings.Contains(detail, "package.json") || !strings.Contains(detail, "bundle.obc.zip") || !strings.Contains(detail, "/publishers/oren-labs") {
		t.Fatalf("detail page missing release links: %s", detail)
	}
	if !strings.Contains(detail, "CORE") || !strings.Contains(detail, "GFX") || !strings.Contains(detail, "main") || !strings.Contains(detail, "1 default(s)") || !strings.Contains(detail, "/packages/oren-labs/plot-demo/source?version=0.1.0") || !strings.Contains(detail, "assets%2Fsource%2Fmain.oren") {
		t.Fatalf("detail page missing manifest metadata: %s", detail)
	}
	if !strings.Contains(detail, `<img class="preview"`) || !strings.Contains(detail, "/screenshots/preview.png") {
		t.Fatalf("detail page missing screenshot: %s", detail)
	}
	publisher := string(rawGet(t, ts, "/publishers/oren-labs"))
	if !strings.Contains(publisher, "Oren Labs") || !strings.Contains(publisher, "Plot Demo") || !strings.Contains(publisher, "/packages/oren-labs/plot-demo") {
		t.Fatalf("publisher page missing public package: %s", publisher)
	}
	if !strings.Contains(publisher, `<img class="preview"`) || !strings.Contains(publisher, "/screenshots/preview.png") {
		t.Fatalf("publisher page missing screenshot: %s", publisher)
	}
	ops := string(rawGet(t, ts, "/ops"))
	if !strings.Contains(ops, "/api/v0/publishers/{publisher}/token") || !strings.Contains(ops, "index.json") || !strings.Contains(ops, "/healthz") || !strings.Contains(ops, "/api/v0/ops/status") {
		t.Fatalf("ops page missing operator endpoints: %s", ops)
	}
	if got := request(t, ts, http.MethodGet, "/api/v0/ops/status", nil, false); got.Code != http.StatusUnauthorized {
		t.Fatalf("unauthenticated ops status=%d body=%s", got.Code, got.Body.String())
	}
	opsStatusResp := request(t, ts, http.MethodGet, "/api/v0/ops/status", nil, true)
	if opsStatusResp.Code != http.StatusOK {
		t.Fatalf("ops status=%d body=%s", opsStatusResp.Code, opsStatusResp.Body.String())
	}
	var opsStatus map[string]any
	if err := json.Unmarshal(opsStatusResp.Body.Bytes(), &opsStatus); err != nil {
		t.Fatalf("decode ops status: %v body=%s", err, opsStatusResp.Body.String())
	}
	if opsStatus["publisher_count"] != float64(1) || opsStatus["public_package_count"] != float64(1) || opsStatus["published_release_count"] != float64(1) || opsStatus["admin_auth_configured"] != true {
		t.Fatalf("bad ops status=%v", opsStatus)
	}
	if opsStatus["bundle_release_count"] != float64(1) || opsStatus["source_release_count"] != float64(1) || opsStatus["source_asset_count"] != float64(1) || opsStatus["permission_default_count"] != float64(1) {
		t.Fatalf("bad ops status=%v", opsStatus)
	}
	opsStatusPage := request(t, ts, http.MethodGet, "/ops/status", nil, true)
	if opsStatusPage.Code != http.StatusOK || !strings.Contains(opsStatusPage.Body.String(), "Operator Status") || !strings.Contains(opsStatusPage.Body.String(), "Release Readiness") || !strings.Contains(opsStatusPage.Body.String(), "Source metadata") || !strings.Contains(opsStatusPage.Body.String(), "Deployment Gates") {
		t.Fatalf("ops status page status=%d body=%s", opsStatusPage.Code, opsStatusPage.Body.String())
	}

	search := getJSON[map[string]any](t, ts, "/api/v0/packages?query=plot&capability=GFX")
	found := search["packages"].([]any)
	if len(found) != 1 {
		t.Fatalf("search found=%v", found)
	}
	if got := rawGet(t, ts, "/api/v0/packages/oren-labs/plot-demo/versions/0.1.0/program.obc"); !bytes.Equal(got, []byte{0xcd, 0x0e, 0x00, 0x01}) {
		t.Fatalf("program bytes=%x", got)
	}
	if got := rawGet(t, ts, "/api/v0/packages/oren-labs/plot-demo/versions/0.1.0/bundle.obc.zip"); len(got) == 0 {
		t.Fatalf("empty release bundle")
	}
	if got := string(rawGet(t, ts, "/api/v0/packages/oren-labs/plot-demo/versions/0.1.0/assets/readme.txt")); got != "asset-ok" {
		t.Fatalf("asset=%q", got)
	}
	if got := string(rawGet(t, ts, "/api/v0/packages/oren-labs/plot-demo/versions/0.1.0/assets/source/main.oren")); got != sourceOren {
		t.Fatalf("source asset=%q", got)
	}
	sourcePage := string(rawGet(t, ts, "/packages/oren-labs/plot-demo/source?version=0.1.0&path=assets/source/main.oren"))
	if !strings.Contains(sourcePage, "AST Outline") || !strings.Contains(sourcePage, `<span class="tok-keyword">fn</span>`) || !strings.Contains(sourcePage, `<span class="tok-decl">main</span>`) || !strings.Contains(sourcePage, `<span class="tok-string">&#34;demo&#34;</span>`) {
		t.Fatalf("source page missing Oren highlighting: %s", sourcePage)
	}
	if got := rawGet(t, ts, "/api/v0/packages/oren-labs/plot-demo/versions/0.1.0/screenshots/preview.png"); !bytes.Equal(got, previewPNG) {
		t.Fatalf("screenshot asset=%x", got)
	}
	if got := request(t, ts, http.MethodGet, "/api/v0/packages/oren-labs/plot-demo/versions/0.1.0/assets/screenshots/preview.png", nil, false); got.Code != http.StatusNotFound {
		t.Fatalf("screenshot unexpectedly served as package asset status=%d body=%s", got.Code, got.Body.String())
	}
	if got := request(t, ts, http.MethodPost, "/api/v0/packages/oren-labs/plot-demo/visibility", map[string]any{"visibility": "private"}, true); got.Code != http.StatusOK {
		t.Fatalf("private visibility status=%d body=%s", got.Code, got.Body.String())
	}
	index = getJSON[map[string]any](t, ts, "/api/v0/index.json")
	if got := len(index["packages"].([]any)); got != 0 {
		t.Fatalf("private package still indexed: %d", got)
	}
	if got := request(t, ts, http.MethodGet, "/api/v0/packages?query=plot", nil, false); got.Code != http.StatusOK {
		t.Fatalf("private search status=%d body=%s", got.Code, got.Body.String())
	} else if found := getPackagesFromBody(t, got.Body.Bytes()); len(found) != 0 {
		t.Fatalf("private package still searchable: %v", found)
	}
	if got := request(t, ts, http.MethodGet, "/packages/oren-labs/plot-demo", nil, false); got.Code != http.StatusNotFound {
		t.Fatalf("private browser package status=%d body=%s", got.Code, got.Body.String())
	}
	if got := request(t, ts, http.MethodGet, "/packages/oren-labs/plot-demo/source?version=0.1.0&path=assets/source/main.oren", nil, false); got.Code != http.StatusNotFound {
		t.Fatalf("private browser source status=%d body=%s", got.Code, got.Body.String())
	}
	if got := string(rawGet(t, ts, "/publishers/oren-labs")); strings.Contains(got, "Plot Demo") {
		t.Fatalf("private package still visible on publisher page: %s", got)
	}
	if got := request(t, ts, http.MethodGet, "/api/v0/packages/oren-labs/plot-demo/versions/0.1.0/program.obc", nil, false); got.Code != http.StatusNotFound {
		t.Fatalf("private unauthenticated download status=%d body=%s", got.Code, got.Body.String())
	}
	if got := request(t, ts, http.MethodGet, "/api/v0/packages/oren-labs/plot-demo/versions/0.1.0/program.obc", nil, true); got.Code != http.StatusOK || !bytes.Equal(got.Body.Bytes(), []byte{0xcd, 0x0e, 0x00, 0x01}) {
		t.Fatalf("private authenticated download status=%d body=%x", got.Code, got.Body.Bytes())
	}
	if got := request(t, ts, http.MethodPost, "/api/v0/packages/oren-labs/plot-demo/visibility", map[string]any{"visibility": "public"}, true); got.Code != http.StatusOK {
		t.Fatalf("public visibility status=%d body=%s", got.Code, got.Body.String())
	}
	if got := request(t, ts, http.MethodPost, "/api/v0/packages/oren-labs/plot-demo/versions/0.1.0/yank", map[string]any{}, true); got.Code != http.StatusOK {
		t.Fatalf("yank status=%d body=%s", got.Code, got.Body.String())
	}
	index = getJSON[map[string]any](t, ts, "/api/v0/index.json")
	if got := len(index["packages"].([]any)); got != 0 {
		t.Fatalf("yanked release still indexed: %d", got)
	}
}

func TestStoreSignsStableIndex(t *testing.T) {
	dir := t.TempDir()
	key, keyPath := writeTestP256Key(t, dir)
	publisherKey, _ := writeTestP256Key(t, t.TempDir())
	svc, err := New(Config{
		DataDir:                dir,
		AdminUser:              "admin",
		AdminPassword:          "secret",
		IndexSigningKeyPEMPath: keyPath,
		Now: func() time.Time {
			return time.Date(2026, 6, 1, 0, 0, 0, 0, time.UTC)
		},
	})
	if err != nil {
		t.Fatal(err)
	}
	ts := httptest.NewServer(svc.Handler())
	defer ts.Close()

	publisherPublicKey := p256PublicKeyX963Base64(&publisherKey.PublicKey)
	if got := request(t, ts, http.MethodPost, "/api/v0/publishers", map[string]any{"id": "oren-labs", "public_keys": []string{publisherPublicKey}}, true); got.Code != http.StatusCreated {
		t.Fatalf("publisher status=%d body=%s", got.Code, got.Body.String())
	}
	if got := request(t, ts, http.MethodPost, "/api/v0/packages", map[string]any{"publisher": "oren-labs", "name": "signed-demo"}, true); got.Code != http.StatusCreated {
		t.Fatalf("package status=%d body=%s", got.Code, got.Body.String())
	}
	upload := map[string]any{
		"version":            "0.1.0",
		"program_obc_base64": base64.StdEncoding.EncodeToString([]byte{0xcd, 0x0e}),
	}
	if got := request(t, ts, http.MethodPost, "/api/v0/packages/oren-labs/signed-demo/versions", upload, true); got.Code != http.StatusCreated {
		t.Fatalf("version status=%d body=%s", got.Code, got.Body.String())
	}
	rel := getJSON[map[string]any](t, ts, "/api/v0/packages/oren-labs/signed-demo/versions/0.1.0")
	manifestHash := rel["manifest_sha256"].(string)
	badPublish := map[string]any{
		"signature_alg":                 "p256-sha256-der",
		"signature_p256_sha256_der_hex": "00",
	}
	if got := request(t, ts, http.MethodPost, "/api/v0/packages/oren-labs/signed-demo/versions/0.1.0/publish", badPublish, true); got.Code != http.StatusBadRequest {
		t.Fatalf("bad publish status=%d body=%s", got.Code, got.Body.String())
	}
	sum := sha256.Sum256([]byte(manifestHash))
	packageSig, err := ecdsa.SignASN1(rand.Reader, publisherKey, sum[:])
	if err != nil {
		t.Fatal(err)
	}
	publish := map[string]any{
		"signature_alg":                 "p256-sha256-der",
		"signature_p256_sha256_der_hex": hex.EncodeToString(packageSig),
	}
	if got := request(t, ts, http.MethodPost, "/api/v0/packages/oren-labs/signed-demo/versions/0.1.0/publish", publish, true); got.Code != http.StatusOK {
		t.Fatalf("publish status=%d body=%s", got.Code, got.Body.String())
	}

	indexA := rawGet(t, ts, "/api/v0/index.json")
	indexB := rawGet(t, ts, "/api/v0/index.json")
	if !bytes.Equal(indexA, indexB) {
		t.Fatalf("index bytes are not stable")
	}
	sig := rawGet(t, ts, "/api/v0/index.json.sig")
	indexSum := sha256.Sum256(indexA)
	if !ecdsa.VerifyASN1(&key.PublicKey, indexSum[:], sig) {
		t.Fatalf("index signature did not verify")
	}
	index := getJSON[map[string]any](t, ts, "/api/v0/index.json")
	packages := index["packages"].([]any)
	entry := packages[0].(map[string]any)
	if entry["signature_alg"] != "p256-sha256-der" || entry["signature_p256_sha256_der_hex"] != hex.EncodeToString(packageSig) {
		t.Fatalf("missing package signature entry=%v", entry)
	}
}

func TestStoreAcceptsBearerAdminTokenHash(t *testing.T) {
	sum := sha256.Sum256([]byte("deploy-token"))
	svc, err := New(Config{
		DataDir:             t.TempDir(),
		AdminTokenSHA256Hex: hex.EncodeToString(sum[:]),
		Now: func() time.Time {
			return time.Date(2026, 6, 1, 0, 0, 0, 0, time.UTC)
		},
	})
	if err != nil {
		t.Fatal(err)
	}
	ts := httptest.NewServer(svc.Handler())
	defer ts.Close()

	if got := requestBearer(t, ts, http.MethodPost, "/api/v0/publishers", map[string]any{"id": "oren-labs"}, "bad-token"); got.Code != http.StatusUnauthorized {
		t.Fatalf("bad bearer status=%d body=%s", got.Code, got.Body.String())
	}
	if got := requestBearer(t, ts, http.MethodPost, "/api/v0/publishers", map[string]any{"id": "oren-labs"}, "deploy-token"); got.Code != http.StatusCreated {
		t.Fatalf("bearer publisher status=%d body=%s", got.Code, got.Body.String())
	}
	if got := request(t, ts, http.MethodPost, "/api/v0/packages", map[string]any{"publisher": "oren-labs", "name": "token-demo"}, true); got.Code != http.StatusUnauthorized {
		t.Fatalf("basic auth should be unavailable without password, status=%d", got.Code)
	}
}

func TestStoreAcceptsPublisherScopedBearerToken(t *testing.T) {
	tokenHash := sha256.Sum256([]byte("oren-labs-token"))
	otherHash := sha256.Sum256([]byte("other-token"))
	svc, err := New(Config{
		DataDir:       t.TempDir(),
		AdminUser:     "admin",
		AdminPassword: "secret",
		Now: func() time.Time {
			return time.Date(2026, 6, 1, 0, 0, 0, 0, time.UTC)
		},
	})
	if err != nil {
		t.Fatal(err)
	}
	ts := httptest.NewServer(svc.Handler())
	defer ts.Close()

	if got := request(t, ts, http.MethodPost, "/api/v0/publishers", map[string]any{
		"id":               "oren-labs",
		"token_sha256_hex": hex.EncodeToString(tokenHash[:]),
		"display_name":     "Oren Labs",
	}, true); got.Code != http.StatusCreated {
		t.Fatalf("publisher status=%d body=%s", got.Code, got.Body.String())
	}
	if got := request(t, ts, http.MethodPost, "/api/v0/publishers", map[string]any{
		"id":               "other-labs",
		"token_sha256_hex": hex.EncodeToString(otherHash[:]),
	}, true); got.Code != http.StatusCreated {
		t.Fatalf("other publisher status=%d body=%s", got.Code, got.Body.String())
	}
	if got := requestBearer(t, ts, http.MethodPost, "/api/v0/packages", map[string]any{"publisher": "oren-labs", "name": "scoped-demo"}, "wrong-token"); got.Code != http.StatusUnauthorized {
		t.Fatalf("wrong publisher token status=%d body=%s", got.Code, got.Body.String())
	}
	if got := requestBearer(t, ts, http.MethodPost, "/api/v0/packages", map[string]any{"publisher": "other-labs", "name": "cross-demo"}, "oren-labs-token"); got.Code != http.StatusUnauthorized {
		t.Fatalf("cross publisher token status=%d body=%s", got.Code, got.Body.String())
	}
	if got := requestBearer(t, ts, http.MethodPost, "/api/v0/packages", map[string]any{"publisher": "oren-labs", "name": "scoped-demo"}, "oren-labs-token"); got.Code != http.StatusCreated {
		t.Fatalf("scoped package status=%d body=%s", got.Code, got.Body.String())
	}
	upload := map[string]any{
		"version":            "0.1.0",
		"program_obc_base64": base64.StdEncoding.EncodeToString([]byte{0xcd, 0x0e}),
	}
	if got := requestBearer(t, ts, http.MethodPost, "/api/v0/packages/oren-labs/scoped-demo/versions", upload, "oren-labs-token"); got.Code != http.StatusCreated {
		t.Fatalf("scoped version status=%d body=%s", got.Code, got.Body.String())
	}
	if got := requestBearer(t, ts, http.MethodPost, "/api/v0/packages/oren-labs/scoped-demo/versions/0.1.0/publish", map[string]any{}, "oren-labs-token"); got.Code != http.StatusOK {
		t.Fatalf("scoped publish status=%d body=%s", got.Code, got.Body.String())
	}
	if got := requestBearer(t, ts, http.MethodPost, "/api/v0/packages/oren-labs/scoped-demo/versions/0.1.0/yank", map[string]any{}, "other-token"); got.Code != http.StatusUnauthorized {
		t.Fatalf("cross yank status=%d body=%s", got.Code, got.Body.String())
	}
	if got := requestBearer(t, ts, http.MethodPost, "/api/v0/packages/oren-labs/scoped-demo/versions/0.1.0/yank", map[string]any{}, "oren-labs-token"); got.Code != http.StatusOK {
		t.Fatalf("scoped yank status=%d body=%s", got.Code, got.Body.String())
	}
	rotatedHash := sha256.Sum256([]byte("rotated-token"))
	if got := requestBearer(t, ts, http.MethodPost, "/api/v0/publishers/oren-labs/token", map[string]any{"token_sha256_hex": hex.EncodeToString(rotatedHash[:])}, "oren-labs-token"); got.Code != http.StatusOK {
		t.Fatalf("rotate token status=%d body=%s", got.Code, got.Body.String())
	}
	if got := requestBearer(t, ts, http.MethodPost, "/api/v0/packages", map[string]any{"publisher": "oren-labs", "name": "old-token-demo"}, "oren-labs-token"); got.Code != http.StatusUnauthorized {
		t.Fatalf("old token after rotation status=%d body=%s", got.Code, got.Body.String())
	}
	if got := requestBearer(t, ts, http.MethodPost, "/api/v0/packages", map[string]any{"publisher": "oren-labs", "name": "rotated-token-demo"}, "rotated-token"); got.Code != http.StatusCreated {
		t.Fatalf("rotated token package status=%d body=%s", got.Code, got.Body.String())
	}
	if got := requestBearer(t, ts, http.MethodDelete, "/api/v0/publishers/oren-labs/token", nil, "rotated-token"); got.Code != http.StatusOK {
		t.Fatalf("revoke token status=%d body=%s", got.Code, got.Body.String())
	}
	if got := requestBearer(t, ts, http.MethodPost, "/api/v0/packages", map[string]any{"publisher": "oren-labs", "name": "revoked-token-demo"}, "rotated-token"); got.Code != http.StatusUnauthorized {
		t.Fatalf("revoked token status=%d body=%s", got.Code, got.Body.String())
	}
	adminHash := sha256.Sum256([]byte("admin-reset-token"))
	if got := request(t, ts, http.MethodPost, "/api/v0/publishers/oren-labs/token", map[string]any{"token_sha256_hex": hex.EncodeToString(adminHash[:])}, true); got.Code != http.StatusOK {
		t.Fatalf("admin token reset status=%d body=%s", got.Code, got.Body.String())
	}
	if got := requestBearer(t, ts, http.MethodPost, "/api/v0/packages", map[string]any{"publisher": "oren-labs", "name": "admin-reset-demo"}, "admin-reset-token"); got.Code != http.StatusCreated {
		t.Fatalf("admin reset token package status=%d body=%s", got.Code, got.Body.String())
	}
}

func request(t *testing.T, ts *httptest.Server, method, path string, body any, auth bool) *httptest.ResponseRecorder {
	t.Helper()
	req := newJSONRequest(t, ts, method, path, body)
	if auth {
		req.SetBasicAuth("admin", "secret")
	}
	return doRequest(t, req)
}

func requestBearer(t *testing.T, ts *httptest.Server, method, path string, body any, token string) *httptest.ResponseRecorder {
	t.Helper()
	req := newJSONRequest(t, ts, method, path, body)
	req.Header.Set("Authorization", "Bearer "+token)
	return doRequest(t, req)
}

func newJSONRequest(t *testing.T, ts *httptest.Server, method, path string, body any) *http.Request {
	t.Helper()
	var reader *bytes.Reader
	if body == nil {
		reader = bytes.NewReader(nil)
	} else {
		b, err := json.Marshal(body)
		if err != nil {
			t.Fatal(err)
		}
		reader = bytes.NewReader(b)
	}
	req, err := http.NewRequest(method, ts.URL+path, reader)
	if err != nil {
		t.Fatal(err)
	}
	req.Header.Set("Content-Type", "application/json")
	return req
}

func doRequest(t *testing.T, req *http.Request) *httptest.ResponseRecorder {
	t.Helper()
	rec := httptest.NewRecorder()
	http.DefaultServeMux = http.NewServeMux()
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	rec.Code = resp.StatusCode
	_, _ = rec.Body.ReadFrom(resp.Body)
	return rec
}

func writeTestP256Key(t *testing.T, dir string) (*ecdsa.PrivateKey, string) {
	t.Helper()
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	der, err := x509.MarshalECPrivateKey(key)
	if err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(dir, "store-key.pem")
	body := pem.EncodeToMemory(&pem.Block{Type: "EC PRIVATE KEY", Bytes: der})
	if err := os.WriteFile(path, body, 0o600); err != nil {
		t.Fatal(err)
	}
	return key, path
}

func p256PublicKeyX963Base64(key *ecdsa.PublicKey) string {
	x := key.X.Bytes()
	y := key.Y.Bytes()
	body := make([]byte, 65)
	body[0] = 4
	copy(body[33-len(x):33], x)
	copy(body[65-len(y):65], y)
	return base64.StdEncoding.EncodeToString(body)
}

func getJSON[T any](t *testing.T, ts *httptest.Server, path string) T {
	t.Helper()
	body := rawGet(t, ts, path)
	var out T
	if err := json.Unmarshal(body, &out); err != nil {
		t.Fatalf("decode %s: %v body=%s", path, err, string(body))
	}
	return out
}

func rawGet(t *testing.T, ts *httptest.Server, path string) []byte {
	t.Helper()
	resp, err := http.Get(ts.URL + path)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("GET %s status=%d", path, resp.StatusCode)
	}
	var buf bytes.Buffer
	_, _ = buf.ReadFrom(resp.Body)
	return buf.Bytes()
}

func getPackagesFromBody(t *testing.T, body []byte) []any {
	t.Helper()
	var out map[string]any
	if err := json.Unmarshal(body, &out); err != nil {
		t.Fatalf("decode packages body: %v body=%s", err, string(body))
	}
	items, _ := out["packages"].([]any)
	return items
}

func testBundleZip(t *testing.T, files map[string][]byte) []byte {
	t.Helper()
	var buf bytes.Buffer
	zw := zip.NewWriter(&buf)
	names := make([]string, 0, len(files))
	for name := range files {
		names = append(names, name)
	}
	sort.Strings(names)
	for _, name := range names {
		w, err := zw.Create(name)
		if err != nil {
			t.Fatal(err)
		}
		if _, err := w.Write(files[name]); err != nil {
			t.Fatal(err)
		}
	}
	if err := zw.Close(); err != nil {
		t.Fatal(err)
	}
	return buf.Bytes()
}
