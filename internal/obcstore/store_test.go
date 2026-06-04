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
	"net/url"
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
	if opsStatus["audit_event_count"].(float64) < 4 {
		t.Fatalf("ops status missing audit count=%v", opsStatus)
	}
	opsStatusPage := request(t, ts, http.MethodGet, "/ops/status", nil, true)
	if opsStatusPage.Code != http.StatusOK || !strings.Contains(opsStatusPage.Body.String(), "Operator Status") || !strings.Contains(opsStatusPage.Body.String(), "Release Readiness") || !strings.Contains(opsStatusPage.Body.String(), "Source metadata") || !strings.Contains(opsStatusPage.Body.String(), "Deployment Gates") {
		t.Fatalf("ops status page status=%d body=%s", opsStatusPage.Code, opsStatusPage.Body.String())
	}
	if got := request(t, ts, http.MethodGet, "/api/v0/ops/releases", nil, false); got.Code != http.StatusUnauthorized {
		t.Fatalf("unauthenticated ops releases=%d body=%s", got.Code, got.Body.String())
	}
	opsReleasesResp := request(t, ts, http.MethodGet, "/api/v0/ops/releases", nil, true)
	if opsReleasesResp.Code != http.StatusOK {
		t.Fatalf("ops releases status=%d body=%s", opsReleasesResp.Code, opsReleasesResp.Body.String())
	}
	var opsReleases map[string]any
	if err := json.Unmarshal(opsReleasesResp.Body.Bytes(), &opsReleases); err != nil {
		t.Fatalf("decode ops releases: %v body=%s", err, opsReleasesResp.Body.String())
	}
	releaseItems := opsReleases["releases"].([]any)
	if len(releaseItems) != 1 {
		t.Fatalf("ops releases items=%v", releaseItems)
	}
	lifecycle := releaseItems[0].(map[string]any)
	if lifecycle["publisher"] != "oren-labs" || lifecycle["name"] != "plot-demo" || lifecycle["version"] != "0.1.0" || lifecycle["latest_published"] != true {
		t.Fatalf("bad ops release lifecycle=%v", lifecycle)
	}
	readiness := lifecycle["readiness"].([]any)
	if !containsAnyString(readiness, "bundle") || !containsAnyString(readiness, "source") || !containsAnyString(readiness, "permissions") {
		t.Fatalf("missing ops readiness=%v", readiness)
	}
	if !strings.Contains(lifecycle["publish_url"].(string), "/publish") || !strings.Contains(lifecycle["yank_url"].(string), "/yank") || !strings.Contains(lifecycle["visibility_url"].(string), "/visibility") {
		t.Fatalf("missing ops lifecycle urls=%v", lifecycle)
	}
	opsReleasesPage := request(t, ts, http.MethodGet, "/ops/releases", nil, true)
	if opsReleasesPage.Code != http.StatusOK || !strings.Contains(opsReleasesPage.Body.String(), "Release Lifecycle") || !strings.Contains(opsReleasesPage.Body.String(), "plot-demo") || !strings.Contains(opsReleasesPage.Body.String(), "/api/v0/packages/oren-labs/plot-demo/versions/0.1.0/yank") || !strings.Contains(opsReleasesPage.Body.String(), "/ops/actions/packages/oren-labs/plot-demo/versions/0.1.0/yank") {
		t.Fatalf("ops releases page status=%d body=%s", opsReleasesPage.Code, opsReleasesPage.Body.String())
	}
	if got := requestForm(t, ts, "/ops/actions/packages/oren-labs/plot-demo/versions/0.1.0/yank", nil, false); got.Code != http.StatusUnauthorized {
		t.Fatalf("unauthenticated ops yank=%d body=%s", got.Code, got.Body.String())
	}
	if got := requestForm(t, ts, "/ops/actions/packages/oren-labs/plot-demo/versions/0.1.0/yank", nil, true); got.Code != http.StatusSeeOther {
		t.Fatalf("ops yank status=%d body=%s", got.Code, got.Body.String())
	}
	yankedRelease := getJSON[map[string]any](t, ts, "/api/v0/packages/oren-labs/plot-demo/versions/0.1.0")
	if yankedRelease["status"] != "yanked" {
		t.Fatalf("ops yank did not update release: %v", yankedRelease)
	}
	if got := requestForm(t, ts, "/ops/actions/packages/oren-labs/plot-demo/versions/0.1.0/publish", nil, true); got.Code != http.StatusSeeOther {
		t.Fatalf("ops publish status=%d body=%s", got.Code, got.Body.String())
	}
	republishedRelease := getJSON[map[string]any](t, ts, "/api/v0/packages/oren-labs/plot-demo/versions/0.1.0")
	if republishedRelease["status"] != "published" {
		t.Fatalf("ops publish did not update release: %v", republishedRelease)
	}
	if got := requestForm(t, ts, "/ops/actions/packages/oren-labs/plot-demo/visibility", map[string]string{"visibility": "private"}, true); got.Code != http.StatusSeeOther {
		t.Fatalf("ops private visibility status=%d body=%s", got.Code, got.Body.String())
	}
	opsPrivateInventory := request(t, ts, http.MethodGet, "/api/v0/ops/releases", nil, true)
	if !strings.Contains(opsPrivateInventory.Body.String(), `"visibility":"private"`) {
		t.Fatalf("ops inventory missing private visibility: %s", opsPrivateInventory.Body.String())
	}
	if got := requestForm(t, ts, "/ops/actions/packages/oren-labs/plot-demo/visibility", map[string]string{"visibility": "public"}, true); got.Code != http.StatusSeeOther {
		t.Fatalf("ops public visibility status=%d body=%s", got.Code, got.Body.String())
	}
	if got := request(t, ts, http.MethodGet, "/api/v0/ops/audit", nil, false); got.Code != http.StatusUnauthorized {
		t.Fatalf("unauthenticated ops audit=%d body=%s", got.Code, got.Body.String())
	}
	auditResp := request(t, ts, http.MethodGet, "/api/v0/ops/audit?limit=20", nil, true)
	if auditResp.Code != http.StatusOK {
		t.Fatalf("ops audit status=%d body=%s", auditResp.Code, auditResp.Body.String())
	}
	var audit map[string]any
	if err := json.Unmarshal(auditResp.Body.Bytes(), &audit); err != nil {
		t.Fatalf("decode ops audit: %v body=%s", err, auditResp.Body.String())
	}
	auditEvents := audit["events"].([]any)
	if !containsAuditEvent(auditEvents, "publisher.create", "publishers/oren-labs") || !containsAuditEvent(auditEvents, "release.create", "packages/oren-labs/plot-demo/versions/0.1.0") || !containsAuditEvent(auditEvents, "ops.release.yanked", "packages/oren-labs/plot-demo/versions/0.1.0") || !containsAuditEvent(auditEvents, "ops.package.visibility", "packages/oren-labs/plot-demo") {
		t.Fatalf("missing audit events=%v", auditEvents)
	}
	auditPage := request(t, ts, http.MethodGet, "/ops/audit", nil, true)
	if auditPage.Code != http.StatusOK || !strings.Contains(auditPage.Body.String(), "Audit Log") || !strings.Contains(auditPage.Body.String(), "ops.package.visibility") {
		t.Fatalf("ops audit page status=%d body=%s", auditPage.Code, auditPage.Body.String())
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
	previousKey, _ := writeTestP256Key(t, t.TempDir())
	publisherKey, _ := writeTestP256Key(t, t.TempDir())
	trustPath := filepath.Join(t.TempDir(), "obc_store_trust.json")
	writeTestTrustBundle(t, trustPath, map[string]*ecdsa.PublicKey{
		"store-2026q2": &key.PublicKey,
		"store-2026q1": &previousKey.PublicKey,
	})
	svc, err := New(Config{
		DataDir:                dir,
		AdminUser:              "admin",
		AdminPassword:          "secret",
		IndexSigningKeyPEMPath: keyPath,
		IndexSigningKeyID:      "store-2026q2",
		TrustBundlePath:        trustPath,
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
	sigResp, err := http.Get(ts.URL + "/api/v0/index.json.sig")
	if err != nil {
		t.Fatal(err)
	}
	defer sigResp.Body.Close()
	if sigResp.Header.Get("X-Oren-Signing-Key-ID") != "store-2026q2" {
		t.Fatalf("missing signing key id header: %q", sigResp.Header.Get("X-Oren-Signing-Key-ID"))
	}
	if sigResp.Header.Get("X-Oren-Signature-Alg") != "p256-sha256-der" {
		t.Fatalf("missing signature alg header: %q", sigResp.Header.Get("X-Oren-Signature-Alg"))
	}
	trust := getJSON[map[string]any](t, ts, "/api/v0/trust/bundle.json")
	if keys := trust["store_keys"].([]any); len(keys) != 2 {
		t.Fatalf("trust bundle should expose active and previous keys: %v", trust)
	}
	statusResp := request(t, ts, http.MethodGet, "/api/v0/ops/status", nil, true)
	if statusResp.Code != http.StatusOK {
		t.Fatalf("ops status=%d body=%s", statusResp.Code, statusResp.Body.String())
	}
	var status map[string]any
	if err := json.Unmarshal(statusResp.Body.Bytes(), &status); err != nil {
		t.Fatal(err)
	}
	if status["index_signing_key_id"] != "store-2026q2" || status["trust_bundle_store_keys"].(float64) != 2 || status["index_signing_key_trusted"] != true {
		t.Fatalf("bad rotation status: %v", status)
	}
	statusIDs := status["trust_bundle_store_key_ids"].([]any)
	if statusIDs[0] != "store-2026q2" || statusIDs[1] != "store-2026q1" {
		t.Fatalf("bad trust key ids: %v", statusIDs)
	}
}

func TestStorePackageUpdateCheck(t *testing.T) {
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

	if got := request(t, ts, http.MethodPost, "/api/v0/publishers", map[string]any{"id": "oren-labs"}, true); got.Code != http.StatusCreated {
		t.Fatalf("publisher status=%d body=%s", got.Code, got.Body.String())
	}
	if got := request(t, ts, http.MethodPost, "/api/v0/packages", map[string]any{"publisher": "oren-labs", "name": "update-demo"}, true); got.Code != http.StatusCreated {
		t.Fatalf("package status=%d body=%s", got.Code, got.Body.String())
	}
	for _, version := range []string{"0.2.0", "0.10.0", "0.10.0-beta.1"} {
		upload := map[string]any{
			"version":            version,
			"program_obc_base64": base64.StdEncoding.EncodeToString([]byte{0xcd, 0x0e}),
		}
		if got := request(t, ts, http.MethodPost, "/api/v0/packages/oren-labs/update-demo/versions", upload, true); got.Code != http.StatusCreated {
			t.Fatalf("version %s status=%d body=%s", version, got.Code, got.Body.String())
		}
		if got := request(t, ts, http.MethodPost, "/api/v0/packages/oren-labs/update-demo/versions/"+version+"/publish", map[string]any{}, true); got.Code != http.StatusOK {
			t.Fatalf("publish %s status=%d body=%s", version, got.Code, got.Body.String())
		}
	}
	status := getJSON[map[string]any](t, ts, "/api/v0/packages/oren-labs/update-demo/update?current_version=0.2.0")
	if status["latest_version"] != "0.10.0" || status["update_available"] != true {
		t.Fatalf("bad update status: %v", status)
	}
	latest := status["latest_release"].(map[string]any)
	if latest["version"] != "0.10.0" || latest["status"] != "published" {
		t.Fatalf("bad latest release: %v", latest)
	}
	current := getJSON[map[string]any](t, ts, "/api/v0/packages/oren-labs/update-demo/update?current_version=0.10.0")
	if current["latest_version"] != "0.10.0" || current["update_available"] != false {
		t.Fatalf("current version should not need update: %v", current)
	}
	if got := request(t, ts, http.MethodGet, "/api/v0/packages/oren-labs/update-demo/update?current_version=bad/version", nil, false); got.Code != http.StatusBadRequest {
		t.Fatalf("bad current_version status=%d body=%s", got.Code, got.Body.String())
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
	auditResp := request(t, ts, http.MethodGet, "/api/v0/ops/audit?limit=50", nil, true)
	if auditResp.Code != http.StatusOK {
		t.Fatalf("ops audit status=%d body=%s", auditResp.Code, auditResp.Body.String())
	}
	body := auditResp.Body.String()
	if !strings.Contains(body, "publisher.token.rotate") || !strings.Contains(body, "publisher.token.revoke") || strings.Contains(body, hex.EncodeToString(rotatedHash[:])) || strings.Contains(body, `"token_sha256_hex"`) || strings.Contains(body, `:"rotated-token"`) {
		t.Fatalf("token audit should record lifecycle without token material: %s", body)
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

func requestForm(t *testing.T, ts *httptest.Server, path string, body map[string]string, auth bool) *httptest.ResponseRecorder {
	t.Helper()
	form := url.Values{}
	for key, value := range body {
		form.Set(key, value)
	}
	req, err := http.NewRequest(http.MethodPost, ts.URL+path, strings.NewReader(form.Encode()))
	if err != nil {
		t.Fatal(err)
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	if auth {
		req.SetBasicAuth("admin", "secret")
	}
	return doRequestNoRedirect(t, req)
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

func doRequestNoRedirect(t *testing.T, req *http.Request) *httptest.ResponseRecorder {
	t.Helper()
	client := *http.DefaultClient
	client.CheckRedirect = func(*http.Request, []*http.Request) error {
		return http.ErrUseLastResponse
	}
	resp, err := client.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	rec := httptest.NewRecorder()
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
	return base64.StdEncoding.EncodeToString(p256PublicKeyX963(key))
}

func containsAnyString(xs []any, want string) bool {
	for _, x := range xs {
		if s, ok := x.(string); ok && s == want {
			return true
		}
	}
	return false
}

func containsAuditEvent(events []any, action, target string) bool {
	for _, raw := range events {
		ev, ok := raw.(map[string]any)
		if ok && ev["action"] == action && ev["target"] == target {
			return true
		}
	}
	return false
}

func writeTestTrustBundle(t *testing.T, path string, storeKeys map[string]*ecdsa.PublicKey) {
	t.Helper()
	ids := make([]string, 0, len(storeKeys))
	for id := range storeKeys {
		ids = append(ids, id)
	}
	sort.Strings(ids)
	sort.Sort(sort.Reverse(sort.StringSlice(ids)))
	keys := make([]map[string]string, 0, len(ids))
	for _, id := range ids {
		keys = append(keys, map[string]string{
			"id":                  id,
			"alg":                 "p256-sha256-der",
			"public_key_x963_b64": p256PublicKeyX963Base64(storeKeys[id]),
		})
	}
	body, err := json.MarshalIndent(map[string]any{
		"schema":       "oren.obc.trust.v0",
		"generated_at": "2026-06-01T00:00:00Z",
		"store_keys":   keys,
	}, "", "  ")
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, append(body, '\n'), 0o644); err != nil {
		t.Fatal(err)
	}
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
