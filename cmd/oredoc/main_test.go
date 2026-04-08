package main

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

const testMetaJSON = `{
  "structs": [
    {
      "name": "User",
      "serde": {
        "version": 1,
        "format": "json",
        "tag": "User",
        "fields": [
          {"name": "id", "ann_type": "u64", "wire": "user_id", "skip": false, "default": null},
          {"name": "name", "ann_type": "string", "skip": false, "default": "guest"},
          {"name": "blob", "ann_type": "bytes", "skip": true, "default": null}
        ]
      }
    }
  ]
}`

func TestRunOredocUsageAndErrors(t *testing.T) {
	cases := []struct {
		name       string
		args       []string
		wantRC     int
		wantStdout string
		wantStderr string
	}{
		{
			name:       "noArgs",
			wantRC:     2,
			wantStderr: "Usage:\n  oredoc openapi <meta.json>",
		},
		{
			name:       "help",
			args:       []string{"help"},
			wantRC:     0,
			wantStdout: "oredoc openapi <meta.json>",
		},
		{
			name:       "unknownCommand",
			args:       []string{"ship-it"},
			wantRC:     2,
			wantStderr: "ERROR: unknown command: ship-it",
		},
		{
			name:       "missingMeta",
			args:       []string{"openapi"},
			wantRC:     2,
			wantStderr: "ERROR: missing <meta.json>",
		},
	}

	for _, tc := range cases {
		var stdout bytes.Buffer
		var stderr bytes.Buffer
		rc := runOredoc("oredoc", tc.args, &stdout, &stderr)
		if rc != tc.wantRC {
			t.Fatalf("%s: rc=%d want=%d stderr=%q", tc.name, rc, tc.wantRC, stderr.String())
		}
		if tc.wantStdout != "" && !bytes.Contains(stdout.Bytes(), []byte(tc.wantStdout)) {
			t.Fatalf("%s: stdout=%q missing %q", tc.name, stdout.String(), tc.wantStdout)
		}
		if tc.wantStderr != "" && !bytes.Contains(stderr.Bytes(), []byte(tc.wantStderr)) {
			t.Fatalf("%s: stderr=%q missing %q", tc.name, stderr.String(), tc.wantStderr)
		}
	}
}

func TestRunOredocOpenAPISuccess(t *testing.T) {
	tempDir := t.TempDir()
	metaPath := filepath.Join(tempDir, "meta.json")
	if err := os.WriteFile(metaPath, []byte(testMetaJSON), 0o644); err != nil {
		t.Fatalf("write meta: %v", err)
	}

	var stdout bytes.Buffer
	var stderr bytes.Buffer
	rc := runOredoc("oredoc", []string{"openapi", metaPath, "--title", "Accounts API", "--version", "1.2.3"}, &stdout, &stderr)
	if rc != 0 {
		t.Fatalf("rc=%d stderr=%q", rc, stderr.String())
	}
	if stderr.Len() != 0 {
		t.Fatalf("unexpected stderr: %q", stderr.String())
	}

	var doc map[string]interface{}
	if err := json.Unmarshal(stdout.Bytes(), &doc); err != nil {
		t.Fatalf("decode stdout json: %v\n%s", err, stdout.String())
	}

	if got := doc["openapi"]; got != "3.1.0" {
		t.Fatalf("openapi=%v want 3.1.0", got)
	}

	info := testMap(t, doc["info"])
	if info["title"] != "Accounts API" {
		t.Fatalf("title=%v want Accounts API", info["title"])
	}
	if info["version"] != "1.2.3" {
		t.Fatalf("version=%v want 1.2.3", info["version"])
	}

	components := testMap(t, doc["components"])
	schemas := testMap(t, components["schemas"])
	userSchema := testMap(t, schemas["User"])
	properties := testMap(t, userSchema["properties"])
	if _, ok := properties["blob"]; ok {
		t.Fatalf("blob should be skipped: %v", properties)
	}
	if _, ok := properties["t"]; !ok {
		t.Fatalf("tag field missing: %v", properties)
	}
	userID := testMap(t, properties["user_id"])
	if userID["type"] != "integer" {
		t.Fatalf("user_id type=%v want integer", userID["type"])
	}
	if userID["minimum"] != float64(0) {
		t.Fatalf("user_id minimum=%v want 0", userID["minimum"])
	}
	required := testStringSlice(t, userSchema["required"])
	if !containsString(required, "t") || !containsString(required, "user_id") {
		t.Fatalf("required=%v want t and user_id", required)
	}
	if containsString(required, "name") {
		t.Fatalf("name should not be required when default is present: %v", required)
	}
}

func TestRunOredocOpenAPIWritesFile(t *testing.T) {
	tempDir := t.TempDir()
	metaPath := filepath.Join(tempDir, "meta.json")
	outPath := filepath.Join(tempDir, "openapi.json")
	if err := os.WriteFile(metaPath, []byte(testMetaJSON), 0o644); err != nil {
		t.Fatalf("write meta: %v", err)
	}

	var stdout bytes.Buffer
	var stderr bytes.Buffer
	rc := runOredoc("oredoc", []string{"openapi", metaPath, "-o", outPath}, &stdout, &stderr)
	if rc != 0 {
		t.Fatalf("rc=%d stderr=%q", rc, stderr.String())
	}
	if stdout.Len() != 0 {
		t.Fatalf("stdout should be empty when writing to file: %q", stdout.String())
	}
	if stderr.Len() != 0 {
		t.Fatalf("unexpected stderr: %q", stderr.String())
	}
	if _, err := os.Stat(outPath); err != nil {
		t.Fatalf("stat output: %v", err)
	}
}

func testMap(t *testing.T, v interface{}) map[string]interface{} {
	t.Helper()
	m, ok := v.(map[string]interface{})
	if !ok {
		t.Fatalf("value is %T, want map[string]interface{}", v)
	}
	return m
}

func testStringSlice(t *testing.T, v interface{}) []string {
	t.Helper()
	items, ok := v.([]interface{})
	if !ok {
		t.Fatalf("value is %T, want []interface{}", v)
	}
	out := make([]string, 0, len(items))
	for _, item := range items {
		s, ok := item.(string)
		if !ok {
			t.Fatalf("required item is %T, want string", item)
		}
		out = append(out, s)
	}
	return out
}

func containsString(items []string, want string) bool {
	for _, item := range items {
		if item == want {
			return true
		}
	}
	return false
}
