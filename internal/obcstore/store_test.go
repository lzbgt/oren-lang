package obcstore

import (
	"bytes"
	"encoding/base64"
	"encoding/json"
	"net/http"
	"net/http/httptest"
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

func request(t *testing.T, ts *httptest.Server, method, path string, body any, auth bool) *httptest.ResponseRecorder {
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
	if auth {
		req.SetBasicAuth("admin", "secret")
	}
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
