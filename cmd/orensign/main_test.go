package main

import (
	"bytes"
	"crypto/ed25519"
	"crypto/rand"
	"os"
	"path/filepath"
	"testing"
)

func TestRunOrensignUsageAndErrors(t *testing.T) {
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
			wantStderr: "Usage:\n  orensign keygen --out <dir>",
		},
		{
			name:       "help",
			args:       []string{"help"},
			wantRC:     0,
			wantStdout: "orensign sign-obc --sk <path> --in <file.obc>",
		},
		{
			name:       "unknownCommand",
			args:       []string{"ship-it"},
			wantRC:     2,
			wantStderr: "ERROR: unknown command: ship-it",
		},
		{
			name:       "keygenMissingOut",
			args:       []string{"keygen"},
			wantRC:     2,
			wantStderr: "ERROR: missing --out",
		},
		{
			name:       "signMissingArgs",
			args:       []string{"sign-obc"},
			wantRC:     2,
			wantStderr: "ERROR: missing --sk or --in",
		},
	}

	for _, tc := range cases {
		var stdout bytes.Buffer
		var stderr bytes.Buffer
		rc := runOrensign("orensign", tc.args, &stdout, &stderr)
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

func TestRunOrensignKeygenSignVerify(t *testing.T) {
	tempDir := t.TempDir()
	skPath := filepath.Join(tempDir, "root_ed25519_sk.bin")
	pkPath := filepath.Join(tempDir, "root_ed25519_pk.bin")
	obcPath := filepath.Join(tempDir, "hello.obc")

	var stdout bytes.Buffer
	var stderr bytes.Buffer
	rc := runOrensign("orensign", []string{"keygen", "--out", tempDir}, &stdout, &stderr)
	if rc != 0 {
		t.Fatalf("keygen rc=%d stderr=%q", rc, stderr.String())
	}
	if _, err := os.Stat(skPath); err != nil {
		t.Fatalf("stat private key: %v", err)
	}
	if _, err := os.Stat(pkPath); err != nil {
		t.Fatalf("stat public key: %v", err)
	}

	if err := os.WriteFile(obcPath, []byte{obcMagic0, obcMagic1, 0, 0}, 0o644); err != nil {
		t.Fatalf("write obc: %v", err)
	}

	stdout.Reset()
	stderr.Reset()
	rc = runOrensign("orensign", []string{"sign-obc", "--sk", skPath, "--in", obcPath}, &stdout, &stderr)
	if rc != 0 {
		t.Fatalf("sign rc=%d stderr=%q", rc, stderr.String())
	}
	if !bytes.Contains(stdout.Bytes(), []byte("Signed: "+obcPath)) {
		t.Fatalf("unexpected sign stdout: %q", stdout.String())
	}

	stdout.Reset()
	stderr.Reset()
	rc = runOrensign("orensign", []string{"verify-obc", "--pk", pkPath, "--in", obcPath}, &stdout, &stderr)
	if rc != 0 {
		t.Fatalf("verify rc=%d stderr=%q", rc, stderr.String())
	}
	if !bytes.Contains(stdout.Bytes(), []byte("OK")) {
		t.Fatalf("unexpected verify stdout: %q", stdout.String())
	}
}

func TestRunOrensignIssueCertWritesCert(t *testing.T) {
	tempDir := t.TempDir()
	_, issuerSK := generateTestKeyPair(t)
	subjectPK, _ := generateTestKeyPair(t)
	issuerSKPath := filepath.Join(tempDir, "issuer_sk.bin")
	subjectPKPath := filepath.Join(tempDir, "subject_pk.bin")
	certPath := filepath.Join(tempDir, "leaf.cert")
	if err := os.WriteFile(issuerSKPath, issuerSK, 0o600); err != nil {
		t.Fatalf("write issuer sk: %v", err)
	}
	if err := os.WriteFile(subjectPKPath, subjectPK, 0o644); err != nil {
		t.Fatalf("write subject pk: %v", err)
	}

	var stdout bytes.Buffer
	var stderr bytes.Buffer
	rc := runOrensign(
		"orensign",
		[]string{
			"issue-cert",
			"--issuer-sk", issuerSKPath,
			"--subject-pk", subjectPKPath,
			"--out", certPath,
			"--can-issue",
			"--allow-domains", "CORE,ENV",
		},
		&stdout,
		&stderr,
	)
	if rc != 0 {
		t.Fatalf("issue-cert rc=%d stderr=%q", rc, stderr.String())
	}
	certBytes, err := os.ReadFile(certPath)
	if err != nil {
		t.Fatalf("read cert: %v", err)
	}
	if !bytes.HasPrefix(certBytes, []byte(certV2Prefix)) {
		t.Fatalf("cert prefix mismatch: %q", certBytes)
	}
}

func TestRunOrensignIssueCertRejectsConflictingAllowDomainFlags(t *testing.T) {
	tempDir := t.TempDir()
	_, issuerSK := generateTestKeyPair(t)
	subjectPK, _ := generateTestKeyPair(t)
	issuerSKPath := filepath.Join(tempDir, "issuer_sk.bin")
	subjectPKPath := filepath.Join(tempDir, "subject_pk.bin")
	certPath := filepath.Join(tempDir, "leaf.cert")
	if err := os.WriteFile(issuerSKPath, issuerSK, 0o600); err != nil {
		t.Fatalf("write issuer sk: %v", err)
	}
	if err := os.WriteFile(subjectPKPath, subjectPK, 0o644); err != nil {
		t.Fatalf("write subject pk: %v", err)
	}

	var stdout bytes.Buffer
	var stderr bytes.Buffer
	rc := runOrensign(
		"orensign",
		[]string{
			"issue-cert",
			"--issuer-sk", issuerSKPath,
			"--subject-pk", subjectPKPath,
			"--out", certPath,
			"--allow-domains", "CORE",
			"--allow-domains-mask", "1",
		},
		&stdout,
		&stderr,
	)
	if rc != 2 {
		t.Fatalf("rc=%d want=2 stderr=%q", rc, stderr.String())
	}
	if !bytes.Contains(stderr.Bytes(), []byte("cannot use both --allow-domains and --allow-domains-mask")) {
		t.Fatalf("unexpected stderr: %q", stderr.String())
	}
}

func generateTestKeyPair(t *testing.T) (ed25519.PublicKey, ed25519.PrivateKey) {
	t.Helper()
	pk, sk, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatalf("generate ed25519 keypair: %v", err)
	}
	return pk, sk
}
