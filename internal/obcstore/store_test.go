package obcstore

import (
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
	if got := request(t, ts, http.MethodPost, "/api/v0/publishers", map[string]any{"id": "oren-labs"}, false); got.Code != http.StatusUnauthorized {
		t.Fatalf("unauthorized publisher status=%d", got.Code)
	}
	if got := request(t, ts, http.MethodPost, "/api/v0/publishers", map[string]any{"id": "oren-labs", "display_name": "Oren Labs"}, true); got.Code != http.StatusCreated {
		t.Fatalf("publisher status=%d body=%s", got.Code, got.Body.String())
	}
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
	upload := map[string]any{
		"version":            "0.1.0",
		"program_obc_base64": base64.StdEncoding.EncodeToString([]byte{0xcd, 0x0e, 0x00, 0x01}),
		"tags":               []string{"science", "gfx"},
		"min_app":            "0.1.0",
		"manifest": map[string]any{
			"title":        "Plot Demo",
			"summary":      "Interactive plot",
			"capabilities": []string{"CORE", "GFX", "NET"},
		},
		"assets": []map[string]any{
			{
				"path":           "assets/readme.txt",
				"media_type":     "text/plain",
				"content_base64": base64.StdEncoding.EncodeToString([]byte("asset-ok")),
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

	home := string(rawGet(t, ts, "/"))
	if !strings.Contains(home, "Plot Demo") || !strings.Contains(home, "/packages/oren-labs/plot-demo") {
		t.Fatalf("home page missing package: %s", home)
	}
	detail := string(rawGet(t, ts, "/packages/oren-labs/plot-demo"))
	if !strings.Contains(detail, "program.obc") || !strings.Contains(detail, "package.json") {
		t.Fatalf("detail page missing release links: %s", detail)
	}
	ops := string(rawGet(t, ts, "/ops"))
	if !strings.Contains(ops, "/api/v0/publishers/{publisher}/token") || !strings.Contains(ops, "index.json") {
		t.Fatalf("ops page missing operator endpoints: %s", ops)
	}

	search := getJSON[map[string]any](t, ts, "/api/v0/packages?query=plot&capability=GFX")
	found := search["packages"].([]any)
	if len(found) != 1 {
		t.Fatalf("search found=%v", found)
	}
	if got := rawGet(t, ts, "/api/v0/packages/oren-labs/plot-demo/versions/0.1.0/program.obc"); !bytes.Equal(got, []byte{0xcd, 0x0e, 0x00, 0x01}) {
		t.Fatalf("program bytes=%x", got)
	}
	if got := string(rawGet(t, ts, "/api/v0/packages/oren-labs/plot-demo/versions/0.1.0/assets/readme.txt")); got != "asset-ok" {
		t.Fatalf("asset=%q", got)
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
