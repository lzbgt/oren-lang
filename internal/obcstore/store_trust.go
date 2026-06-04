package obcstore

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/hex"
	"encoding/pem"
	"errors"
	"fmt"
	"math/big"
	"os"
	"path/filepath"
	"strings"
)

type trustBundleFile struct {
	Schema    string          `json:"schema"`
	StoreKeys []trustStoreKey `json:"store_keys"`
}

type trustStoreKey struct {
	ID               string `json:"id"`
	Alg              string `json:"alg"`
	PublicKeyX963B64 string `json:"public_key_x963_b64"`
}

func loadP256PrivateKey(path string) (*ecdsa.PrivateKey, error) {
	body, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	block, _ := pem.Decode(body)
	if block == nil {
		return nil, fmt.Errorf("missing PEM private key in %s", path)
	}
	var key any
	if parsed, err := x509.ParseECPrivateKey(block.Bytes); err == nil {
		key = parsed
	} else if parsed, err := x509.ParsePKCS8PrivateKey(block.Bytes); err == nil {
		key = parsed
	} else {
		return nil, fmt.Errorf("failed to parse P-256 private key %s", path)
	}
	ec, ok := key.(*ecdsa.PrivateKey)
	if !ok || ec.Curve == nil || ec.Curve.Params().Name != elliptic.P256().Params().Name {
		return nil, fmt.Errorf("index signing key must be ECDSA P-256: %s", path)
	}
	return ec, nil
}

func parseP256PublicKeyX963Base64(raw string) (*ecdsa.PublicKey, error) {
	body, err := base64.StdEncoding.DecodeString(raw)
	if err != nil {
		return nil, err
	}
	if len(body) != 65 || body[0] != 4 {
		return nil, errors.New("publisher public key must be 65-byte X9.63 P-256")
	}
	x := new(big.Int).SetBytes(body[1:33])
	y := new(big.Int).SetBytes(body[33:65])
	curve := elliptic.P256()
	if !curve.IsOnCurve(x, y) {
		return nil, errors.New("publisher public key is not on P-256")
	}
	return &ecdsa.PublicKey{Curve: curve, X: x, Y: y}, nil
}

func (s *Service) currentTrustBundlePath() string {
	if s.trustBundlePath != "" {
		return s.trustBundlePath
	}
	return filepath.Join(s.dataDir, "trust", "obc_store_trust.json")
}

func (s *Service) trustBundleStoreKeyIDs() (bool, []string, error) {
	path := s.currentTrustBundlePath()
	if !fileExists(path) {
		return false, nil, nil
	}
	bundle, err := readJSONFile[trustBundleFile](path)
	if err != nil {
		return true, nil, err
	}
	ids := make([]string, 0, len(bundle.StoreKeys))
	for _, key := range bundle.StoreKeys {
		id := strings.TrimSpace(key.ID)
		if id != "" {
			ids = append(ids, id)
		}
		if key.Alg != "p256-sha256-der" {
			return true, ids, fmt.Errorf("trust bundle store key %q uses unsupported alg %q", id, key.Alg)
		}
		if _, err := parseP256PublicKeyX963Base64(key.PublicKeyX963B64); err != nil {
			return true, ids, fmt.Errorf("trust bundle store key %q: %w", id, err)
		}
	}
	return true, ids, nil
}

func derivedP256KeyID(key *ecdsa.PublicKey) string {
	body := p256PublicKeyX963(key)
	sum := sha256.Sum256(body)
	return "p256-" + hex.EncodeToString(sum[:8])
}

func p256PublicKeyX963(key *ecdsa.PublicKey) []byte {
	x := key.X.Bytes()
	y := key.Y.Bytes()
	body := make([]byte, 65)
	body[0] = 4
	copy(body[33-len(x):33], x)
	copy(body[65-len(y):65], y)
	return body
}

func safeKeyID(s string) bool {
	if s == "" || len(s) > 120 {
		return false
	}
	for _, r := range s {
		if (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') || (r >= '0' && r <= '9') || r == '-' || r == '_' || r == '.' {
			continue
		}
		return false
	}
	return true
}
