package obcstore

import (
	"bytes"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"crypto/x509"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"encoding/pem"
	"errors"
	"fmt"
	"html/template"
	"io"
	"math/big"
	"net/http"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"
)

const (
	indexSchema    = "oren.obc.store.index.v0"
	manifestSchema = "oren.obc.package.v0"
)

var (
	siteHomeTemplate    = template.Must(template.New("store-home").Parse(siteHomeHTML))
	sitePackageTemplate = template.Must(template.New("store-package").Parse(sitePackageHTML))
	siteOpsTemplate     = template.Must(template.New("store-ops").Parse(siteOpsHTML))
)

type Config struct {
	DataDir                string
	AdminUser              string
	AdminPassword          string
	AdminTokenSHA256Hex    string
	IndexSigningKeyPEMPath string
	Now                    func() time.Time
}

type Service struct {
	dataDir        string
	adminUser      string
	adminPassword  string
	adminTokenHash []byte
	indexSigner    *ecdsa.PrivateKey
	now            func() time.Time
	mu             sync.Mutex
}

type Publisher struct {
	ID             string   `json:"id"`
	DisplayName    string   `json:"display_name,omitempty"`
	PublicKeys     []string `json:"public_keys,omitempty"`
	TokenSHA256Hex string   `json:"token_sha256_hex,omitempty"`
	Status         string   `json:"status,omitempty"`
}

type PackageMeta struct {
	Publisher string   `json:"publisher"`
	Name      string   `json:"name"`
	Title     string   `json:"title,omitempty"`
	Summary   string   `json:"summary,omitempty"`
	Tags      []string `json:"tags,omitempty"`
	Status    string   `json:"status,omitempty"`
}

type PackageListItem struct {
	ID        string   `json:"id"`
	Publisher string   `json:"publisher"`
	Name      string   `json:"name"`
	Version   string   `json:"version"`
	Title     string   `json:"title,omitempty"`
	Summary   string   `json:"summary,omitempty"`
	Tags      []string `json:"tags,omitempty"`
}

type AssetUpload struct {
	Path          string `json:"path"`
	MediaType     string `json:"media_type,omitempty"`
	ContentBase64 string `json:"content_base64"`
}

type ReleaseUpload struct {
	Version                   string                 `json:"version"`
	Manifest                  map[string]any         `json:"manifest,omitempty"`
	ProgramOBCBase64          string                 `json:"program_obc_base64"`
	Assets                    []AssetUpload          `json:"assets,omitempty"`
	Tags                      []string               `json:"tags,omitempty"`
	MinApp                    string                 `json:"min_app,omitempty"`
	SignatureAlg              string                 `json:"signature_alg,omitempty"`
	SignatureP256SHA256DERHex string                 `json:"signature_p256_sha256_der_hex,omitempty"`
	Metadata                  map[string]interface{} `json:"metadata,omitempty"`
}

type ArtifactUpload struct {
	Path          string `json:"path"`
	MediaType     string `json:"media_type,omitempty"`
	ContentBase64 string `json:"content_base64"`
}

type PublisherTokenUpdate struct {
	TokenSHA256Hex string `json:"token_sha256_hex"`
}

type ReleaseMeta struct {
	Publisher                 string    `json:"publisher"`
	Name                      string    `json:"name"`
	Version                   string    `json:"version"`
	Status                    string    `json:"status"`
	ManifestPath              string    `json:"manifest"`
	ManifestSHA256            string    `json:"manifest_sha256"`
	OBCSHA256                 string    `json:"obc_sha256"`
	SignatureAlg              string    `json:"signature_alg,omitempty"`
	SignatureP256SHA256DERHex string    `json:"signature_p256_sha256_der_hex,omitempty"`
	Tags                      []string  `json:"tags,omitempty"`
	MinApp                    string    `json:"min_app,omitempty"`
	CreatedAt                 time.Time `json:"created_at"`
	UpdatedAt                 time.Time `json:"updated_at"`
}

type ReleasePublishRequest struct {
	SignatureAlg              string `json:"signature_alg,omitempty"`
	SignatureP256SHA256DERHex string `json:"signature_p256_sha256_der_hex,omitempty"`
}

func New(cfg Config) (*Service, error) {
	if cfg.DataDir == "" {
		return nil, errors.New("data dir is required")
	}
	now := cfg.Now
	if now == nil {
		now = time.Now
	}
	if err := os.MkdirAll(cfg.DataDir, 0o755); err != nil {
		return nil, err
	}
	var indexSigner *ecdsa.PrivateKey
	if cfg.IndexSigningKeyPEMPath != "" {
		key, err := loadP256PrivateKey(cfg.IndexSigningKeyPEMPath)
		if err != nil {
			return nil, err
		}
		indexSigner = key
	}
	var adminTokenHash []byte
	if cfg.AdminTokenSHA256Hex != "" {
		body, err := hex.DecodeString(strings.TrimSpace(cfg.AdminTokenSHA256Hex))
		if err != nil || len(body) != sha256.Size {
			return nil, errors.New("admin token hash must be a SHA-256 hex digest")
		}
		adminTokenHash = body
	}
	return &Service{
		dataDir:        cfg.DataDir,
		adminUser:      cfg.AdminUser,
		adminPassword:  cfg.AdminPassword,
		adminTokenHash: adminTokenHash,
		indexSigner:    indexSigner,
		now:            now,
	}, nil
}

func (s *Service) Handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("/", s.handleSiteHome)
	mux.HandleFunc("/ops", s.handleSiteOps)
	mux.HandleFunc("/packages/", s.handleSitePackage)
	mux.HandleFunc("/api/v0/health", s.handleHealth)
	mux.HandleFunc("/api/v0/me", s.handleMe)
	mux.HandleFunc("/api/v0/publishers", s.handlePublishers)
	mux.HandleFunc("/api/v0/publishers/", s.handlePublisherPath)
	mux.HandleFunc("/api/v0/index.json", s.handleIndex)
	mux.HandleFunc("/api/v0/index.json.sig", s.handleIndexSignature)
	mux.HandleFunc("/api/v0/trust/bundle.json", s.handleTrustBundle)
	mux.HandleFunc("/api/v0/packages", s.handlePackagesRoot)
	mux.HandleFunc("/api/v0/packages/", s.handlePackagePath)
	mux.HandleFunc("/api/v0/artifacts/sha256/", s.handleArtifactByHash)
	return mux
}

func (s *Service) handleHealth(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{"status": "ok", "schema": indexSchema})
}

func (s *Service) handleSiteHome(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path != "/" {
		http.NotFound(w, r)
		return
	}
	if r.Method != http.MethodGet {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	items, err := s.packageSearchItems(r)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	renderHTML(w, siteHomeTemplate, map[string]any{
		"Query":      r.URL.Query().Get("query"),
		"Tag":        r.URL.Query().Get("tag"),
		"Capability": r.URL.Query().Get("capability"),
		"Packages":   items,
	})
}

func (s *Service) handleSitePackage(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	rest := strings.TrimPrefix(r.URL.Path, "/packages/")
	parts := strings.Split(rest, "/")
	if len(parts) != 2 || !safeID(parts[0]) || !safeID(parts[1]) {
		http.NotFound(w, r)
		return
	}
	pub, name := parts[0], parts[1]
	meta, err := readJSONFile[PackageMeta](s.packageMetaPath(pub, name))
	if err != nil {
		http.NotFound(w, r)
		return
	}
	releases, err := s.packageReleases(pub, name)
	if err != nil {
		http.NotFound(w, r)
		return
	}
	published := make([]ReleaseMeta, 0, len(releases))
	for _, rel := range releases {
		if rel.Status == "published" {
			published = append(published, rel)
		}
	}
	renderHTML(w, sitePackageTemplate, map[string]any{
		"Meta":     meta,
		"Releases": published,
	})
}

func (s *Service) handleSiteOps(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path != "/ops" {
		http.NotFound(w, r)
		return
	}
	if r.Method != http.MethodGet {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	renderHTML(w, siteOpsTemplate, nil)
}

func (s *Service) handleMe(w http.ResponseWriter, r *http.Request) {
	if !s.requireAdmin(w, r) {
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"user": s.adminUser, "role": "admin"})
}

func (s *Service) handlePublishers(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	if !s.requireAdmin(w, r) {
		return
	}
	var p Publisher
	if !decodeJSON(w, r, &p) {
		return
	}
	if !safeID(p.ID) {
		http.Error(w, "invalid publisher id", http.StatusBadRequest)
		return
	}
	if p.TokenSHA256Hex != "" && !validSHA256Hex(p.TokenSHA256Hex) {
		http.Error(w, "invalid publisher token hash", http.StatusBadRequest)
		return
	}
	p.TokenSHA256Hex = strings.ToLower(strings.TrimSpace(p.TokenSHA256Hex))
	if p.Status == "" {
		p.Status = "active"
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	if err := writeJSONFile(s.publisherPath(p.ID), p); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	writeJSON(w, http.StatusCreated, p)
}

func (s *Service) handlePublisherPath(w http.ResponseWriter, r *http.Request) {
	rest := strings.TrimPrefix(r.URL.Path, "/api/v0/publishers/")
	parts := strings.Split(rest, "/")
	if len(parts) != 2 || !safeID(parts[0]) || parts[1] != "token" {
		http.NotFound(w, r)
		return
	}
	switch r.Method {
	case http.MethodPost:
		s.rotatePublisherToken(w, r, parts[0])
	case http.MethodDelete:
		s.revokePublisherToken(w, r, parts[0])
	default:
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
	}
}

func (s *Service) handlePackagesRoot(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		s.listPackages(w, r)
	case http.MethodPost:
		s.createPackage(w, r)
	default:
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
	}
}

func (s *Service) handlePackagePath(w http.ResponseWriter, r *http.Request) {
	rest := strings.TrimPrefix(r.URL.Path, "/api/v0/packages/")
	parts := strings.Split(rest, "/")
	if len(parts) < 2 || !safeID(parts[0]) || !safeID(parts[1]) {
		http.NotFound(w, r)
		return
	}
	pub, name := parts[0], parts[1]
	if len(parts) == 2 {
		if r.Method != http.MethodGet {
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			return
		}
		s.getPackage(w, pub, name)
		return
	}
	if parts[2] != "versions" {
		http.NotFound(w, r)
		return
	}
	if len(parts) == 3 {
		if r.Method == http.MethodGet {
			s.listVersions(w, pub, name)
			return
		}
		if r.Method == http.MethodPost {
			if !s.requirePublisher(w, r, pub) {
				return
			}
			s.createVersion(w, r, pub, name)
			return
		}
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	version := parts[3]
	if !safeVersion(version) {
		http.NotFound(w, r)
		return
	}
	if len(parts) == 4 && r.Method == http.MethodGet {
		s.getRelease(w, pub, name, version)
		return
	}
	if len(parts) == 5 && r.Method == http.MethodPost {
		if !s.requirePublisher(w, r, pub) {
			return
		}
		switch parts[4] {
		case "publish":
			s.publishRelease(w, r, pub, name, version)
		case "yank":
			s.setReleaseStatus(w, pub, name, version, "yanked")
		case "artifacts":
			s.uploadArtifact(w, r, pub, name, version)
		default:
			http.NotFound(w, r)
		}
		return
	}
	if len(parts) >= 5 && r.Method == http.MethodGet {
		s.downloadReleaseFile(w, r, pub, name, version, parts[4:])
		return
	}
	http.NotFound(w, r)
}

func (s *Service) createPackage(w http.ResponseWriter, r *http.Request) {
	var p PackageMeta
	if !decodeJSON(w, r, &p) {
		return
	}
	if !safeID(p.Publisher) || !safeID(p.Name) {
		http.Error(w, "invalid package identity", http.StatusBadRequest)
		return
	}
	if !s.requirePublisher(w, r, p.Publisher) {
		return
	}
	if p.Status == "" {
		p.Status = "active"
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	if _, err := os.Stat(s.publisherPath(p.Publisher)); err != nil {
		http.Error(w, "publisher not found", http.StatusNotFound)
		return
	}
	if err := writeJSONFile(s.packageMetaPath(p.Publisher, p.Name), p); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	writeJSON(w, http.StatusCreated, p)
}

func (s *Service) rotatePublisherToken(w http.ResponseWriter, r *http.Request, publisherID string) {
	if !s.requirePublisher(w, r, publisherID) {
		return
	}
	var update PublisherTokenUpdate
	if !decodeJSON(w, r, &update) {
		return
	}
	if !validSHA256Hex(update.TokenSHA256Hex) {
		http.Error(w, "invalid publisher token hash", http.StatusBadRequest)
		return
	}
	if !s.setPublisherTokenHash(w, publisherID, strings.ToLower(strings.TrimSpace(update.TokenSHA256Hex))) {
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"publisher": publisherID, "token_configured": true})
}

func (s *Service) revokePublisherToken(w http.ResponseWriter, r *http.Request, publisherID string) {
	if !s.requirePublisher(w, r, publisherID) {
		return
	}
	if !s.setPublisherTokenHash(w, publisherID, "") {
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"publisher": publisherID, "token_configured": false})
}

func (s *Service) setPublisherTokenHash(w http.ResponseWriter, publisherID, tokenHash string) bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	path := s.publisherPath(publisherID)
	publisher, err := readJSONFile[Publisher](path)
	if err != nil {
		http.Error(w, "publisher not found", http.StatusNotFound)
		return false
	}
	publisher.TokenSHA256Hex = tokenHash
	if err := writeJSONFile(path, publisher); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return false
	}
	return true
}

func (s *Service) createVersion(w http.ResponseWriter, r *http.Request, pub, name string) {
	var upload ReleaseUpload
	if !decodeJSON(w, r, &upload) {
		return
	}
	if !safeVersion(upload.Version) || upload.ProgramOBCBase64 == "" {
		http.Error(w, "invalid release upload", http.StatusBadRequest)
		return
	}
	program, err := base64.StdEncoding.DecodeString(upload.ProgramOBCBase64)
	if err != nil {
		http.Error(w, "invalid program_obc_base64", http.StatusBadRequest)
		return
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	if _, err := os.Stat(s.packageMetaPath(pub, name)); err != nil {
		http.Error(w, "package not found", http.StatusNotFound)
		return
	}
	dir := s.releaseDir(pub, name, upload.Version)
	if _, err := os.Stat(filepath.Join(dir, "release.json")); err == nil {
		http.Error(w, "release already exists", http.StatusConflict)
		return
	}
	if err := os.MkdirAll(filepath.Join(dir, "assets"), 0o755); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	if err := os.WriteFile(filepath.Join(dir, "program.obc"), program, 0o644); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	assetEntries, ok := s.writeAssets(w, dir, upload.Assets)
	if !ok {
		return
	}
	obcHash := sha256Hex(program)
	manifest := upload.Manifest
	if manifest == nil {
		manifest = map[string]any{}
	}
	manifest["schema"] = manifestSchema
	manifest["publisher"] = pub
	manifest["name"] = name
	manifest["version"] = upload.Version
	manifest["entry_obc"] = "program.obc"
	manifest["obc_sha256"] = obcHash
	if len(assetEntries) > 0 {
		manifest["assets"] = assetEntries
	}
	manifestBytes, err := marshalJSON(manifest)
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	if err := os.WriteFile(filepath.Join(dir, "package.json"), manifestBytes, 0o644); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	now := s.now().UTC()
	rel := ReleaseMeta{
		Publisher:                 pub,
		Name:                      name,
		Version:                   upload.Version,
		Status:                    "draft",
		ManifestPath:              fmt.Sprintf("packages/%s/%s/versions/%s/package.json", pub, name, upload.Version),
		ManifestSHA256:            sha256Hex(manifestBytes),
		OBCSHA256:                 obcHash,
		SignatureAlg:              upload.SignatureAlg,
		SignatureP256SHA256DERHex: strings.ToLower(upload.SignatureP256SHA256DERHex),
		Tags:                      upload.Tags,
		MinApp:                    upload.MinApp,
		CreatedAt:                 now,
		UpdatedAt:                 now,
	}
	if err := writeJSONFile(filepath.Join(dir, "release.json"), rel); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	writeJSON(w, http.StatusCreated, rel)
}

func (s *Service) uploadArtifact(w http.ResponseWriter, r *http.Request, pub, name, version string) {
	var upload ArtifactUpload
	if !decodeJSON(w, r, &upload) {
		return
	}
	if !safeRelPath(upload.Path) || upload.ContentBase64 == "" {
		http.Error(w, "invalid artifact upload", http.StatusBadRequest)
		return
	}
	body, err := base64.StdEncoding.DecodeString(upload.ContentBase64)
	if err != nil {
		http.Error(w, "invalid content_base64", http.StatusBadRequest)
		return
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	dir := s.releaseDir(pub, name, version)
	rel, err := readJSONFile[ReleaseMeta](filepath.Join(dir, "release.json"))
	if err != nil {
		http.Error(w, "release not found", http.StatusNotFound)
		return
	}
	target := filepath.Join(dir, filepath.FromSlash(upload.Path))
	if err := os.MkdirAll(filepath.Dir(target), 0o755); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	if err := os.WriteFile(target, body, 0o644); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	rel.UpdatedAt = s.now().UTC()
	if err := writeJSONFile(filepath.Join(dir, "release.json"), rel); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	writeJSON(w, http.StatusCreated, map[string]any{"path": upload.Path, "sha256": sha256Hex(body), "size": len(body)})
}

func (s *Service) writeAssets(w http.ResponseWriter, dir string, assets []AssetUpload) ([]map[string]any, bool) {
	out := make([]map[string]any, 0, len(assets))
	for _, asset := range assets {
		if !safeRelPath(asset.Path) || asset.ContentBase64 == "" {
			http.Error(w, "invalid asset upload", http.StatusBadRequest)
			return nil, false
		}
		body, err := base64.StdEncoding.DecodeString(asset.ContentBase64)
		if err != nil {
			http.Error(w, "invalid asset content_base64", http.StatusBadRequest)
			return nil, false
		}
		target := filepath.Join(dir, filepath.FromSlash(asset.Path))
		if err := os.MkdirAll(filepath.Dir(target), 0o755); err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return nil, false
		}
		if err := os.WriteFile(target, body, 0o644); err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return nil, false
		}
		out = append(out, map[string]any{
			"path":       filepath.ToSlash(asset.Path),
			"sha256":     sha256Hex(body),
			"size":       len(body),
			"media_type": asset.MediaType,
		})
	}
	return out, true
}

func (s *Service) publishRelease(w http.ResponseWriter, r *http.Request, pub, name, version string) {
	var req ReleasePublishRequest
	if !decodeOptionalJSON(w, r, &req) {
		return
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	path := filepath.Join(s.releaseDir(pub, name, version), "release.json")
	rel, err := readJSONFile[ReleaseMeta](path)
	if err != nil {
		http.Error(w, "release not found", http.StatusNotFound)
		return
	}
	if req.SignatureAlg != "" || req.SignatureP256SHA256DERHex != "" {
		if req.SignatureAlg != "p256-sha256-der" {
			http.Error(w, "unsupported package signature algorithm", http.StatusBadRequest)
			return
		}
		signature := decodeHex(req.SignatureP256SHA256DERHex)
		if len(signature) == 0 {
			http.Error(w, "invalid package signature", http.StatusBadRequest)
			return
		}
		if err := s.verifyPublisherSignature(pub, []byte(rel.ManifestSHA256), signature); err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
		rel.SignatureAlg = req.SignatureAlg
		rel.SignatureP256SHA256DERHex = strings.ToLower(req.SignatureP256SHA256DERHex)
	}
	rel.Status = "published"
	rel.UpdatedAt = s.now().UTC()
	if err := writeJSONFile(path, rel); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	writeJSON(w, http.StatusOK, rel)
}

func (s *Service) setReleaseStatus(w http.ResponseWriter, pub, name, version, status string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	path := filepath.Join(s.releaseDir(pub, name, version), "release.json")
	rel, err := readJSONFile[ReleaseMeta](path)
	if err != nil {
		http.Error(w, "release not found", http.StatusNotFound)
		return
	}
	rel.Status = status
	rel.UpdatedAt = s.now().UTC()
	if err := writeJSONFile(path, rel); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	writeJSON(w, http.StatusOK, rel)
}

func (s *Service) verifyPublisherSignature(pub string, message []byte, signature []byte) error {
	publisher, err := readJSONFile[Publisher](s.publisherPath(pub))
	if err != nil || len(publisher.PublicKeys) == 0 {
		return nil
	}
	sum := sha256.Sum256(message)
	for _, raw := range publisher.PublicKeys {
		key, err := parseP256PublicKeyX963Base64(raw)
		if err == nil && ecdsa.VerifyASN1(key, sum[:], signature) {
			return nil
		}
	}
	return errors.New("publisher signature verification failed")
}

func decodeOptionalJSON(w http.ResponseWriter, r *http.Request, dst any) bool {
	defer r.Body.Close()
	body, err := io.ReadAll(io.LimitReader(r.Body, 1<<20))
	if err != nil {
		http.Error(w, "invalid JSON: "+err.Error(), http.StatusBadRequest)
		return false
	}
	if len(bytes.TrimSpace(body)) == 0 {
		return true
	}
	dec := json.NewDecoder(bytes.NewReader(body))
	dec.DisallowUnknownFields()
	if err := dec.Decode(dst); err != nil {
		http.Error(w, "invalid JSON: "+err.Error(), http.StatusBadRequest)
		return false
	}
	return true
}

func (s *Service) listPackages(w http.ResponseWriter, r *http.Request) {
	items, err := s.packageSearchItems(r)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"packages": items})
}

func (s *Service) packageSearchItems(r *http.Request) ([]PackageListItem, error) {
	q := strings.ToLower(r.URL.Query().Get("query"))
	tag := strings.ToLower(r.URL.Query().Get("tag"))
	capability := strings.ToLower(r.URL.Query().Get("capability"))
	limit := parseLimit(r.URL.Query().Get("limit"), 50)
	releases, err := s.publishedReleases()
	if err != nil {
		return nil, err
	}
	items := make([]PackageListItem, 0)
	for _, rel := range releases {
		meta, _ := readJSONFile[PackageMeta](s.packageMetaPath(rel.Publisher, rel.Name))
		if q != "" && !strings.Contains(strings.ToLower(rel.Publisher+"/"+rel.Name+" "+meta.Title+" "+meta.Summary), q) {
			continue
		}
		if tag != "" && !containsLower(rel.Tags, tag) && !containsLower(meta.Tags, tag) {
			continue
		}
		if capability != "" && !manifestHasCapability(s.releaseDir(rel.Publisher, rel.Name, rel.Version), capability) {
			continue
		}
		items = append(items, PackageListItem{
			ID:        rel.Publisher + "/" + rel.Name,
			Publisher: rel.Publisher,
			Name:      rel.Name,
			Version:   rel.Version,
			Title:     meta.Title,
			Summary:   meta.Summary,
			Tags:      append(meta.Tags, rel.Tags...),
		})
		if len(items) >= limit {
			break
		}
	}
	return items, nil
}

func (s *Service) getPackage(w http.ResponseWriter, pub, name string) {
	meta, err := readJSONFile[PackageMeta](s.packageMetaPath(pub, name))
	if err != nil {
		http.NotFound(w, nil)
		return
	}
	writeJSON(w, http.StatusOK, meta)
}

func (s *Service) listVersions(w http.ResponseWriter, pub, name string) {
	releases, err := s.packageReleases(pub, name)
	if err != nil {
		http.NotFound(w, nil)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"versions": releases})
}

func (s *Service) packageReleases(pub, name string) ([]ReleaseMeta, error) {
	dir := filepath.Join(s.packageDir(pub, name))
	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil, err
	}
	var releases []ReleaseMeta
	for _, ent := range entries {
		if !ent.IsDir() {
			continue
		}
		rel, err := readJSONFile[ReleaseMeta](filepath.Join(dir, ent.Name(), "release.json"))
		if err == nil {
			releases = append(releases, rel)
		}
	}
	sort.Slice(releases, func(i, j int) bool { return releases[i].Version < releases[j].Version })
	return releases, nil
}

func (s *Service) getRelease(w http.ResponseWriter, pub, name, version string) {
	rel, err := readJSONFile[ReleaseMeta](filepath.Join(s.releaseDir(pub, name, version), "release.json"))
	if err != nil {
		http.NotFound(w, nil)
		return
	}
	writeJSON(w, http.StatusOK, rel)
}

func (s *Service) downloadReleaseFile(w http.ResponseWriter, r *http.Request, pub, name, version string, tail []string) {
	var rel string
	switch tail[0] {
	case "package.json":
		rel = "package.json"
	case "program.obc":
		rel = "program.obc"
	case "assets":
		if len(tail) < 2 {
			http.NotFound(w, r)
			return
		}
		assetPath := strings.Join(tail[1:], "/")
		if !safeRelPath("assets/" + assetPath) {
			http.NotFound(w, r)
			return
		}
		rel = "assets/" + assetPath
	default:
		http.NotFound(w, r)
		return
	}
	http.ServeFile(w, r, filepath.Join(s.releaseDir(pub, name, version), filepath.FromSlash(rel)))
}

func (s *Service) handleIndex(w http.ResponseWriter, _ *http.Request) {
	body, err := s.indexJSON()
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write(body)
}

func (s *Service) indexJSON() ([]byte, error) {
	releases, err := s.publishedReleases()
	if err != nil {
		return nil, err
	}
	items := make([]map[string]any, 0, len(releases))
	generatedAt := time.Unix(0, 0).UTC()
	for _, rel := range releases {
		if rel.UpdatedAt.After(generatedAt) {
			generatedAt = rel.UpdatedAt
		}
		item := map[string]any{
			"id":              rel.Publisher + "/" + rel.Name,
			"version":         rel.Version,
			"manifest":        rel.ManifestPath,
			"manifest_sha256": rel.ManifestSHA256,
			"tags":            rel.Tags,
			"min_app":         rel.MinApp,
		}
		if rel.SignatureAlg != "" {
			item["signature_alg"] = rel.SignatureAlg
			item["signature_p256_sha256_der_hex"] = rel.SignatureP256SHA256DERHex
		}
		items = append(items, item)
	}
	return marshalJSON(map[string]any{
		"schema":       indexSchema,
		"generated_at": generatedAt.UTC().Format(time.RFC3339),
		"packages":     items,
	})
}

func (s *Service) handleIndexSignature(w http.ResponseWriter, r *http.Request) {
	if s.indexSigner == nil {
		http.ServeFile(w, r, filepath.Join(s.dataDir, "index.json.sig"))
		return
	}
	indexBody, err := s.indexJSON()
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	sum := sha256.Sum256(indexBody)
	sig, err := ecdsa.SignASN1(rand.Reader, s.indexSigner, sum[:])
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "application/octet-stream")
	w.Header().Set("Cache-Control", "no-store")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write(sig)
}

func (s *Service) handleTrustBundle(w http.ResponseWriter, r *http.Request) {
	http.ServeFile(w, r, filepath.Join(s.dataDir, "trust", "obc_store_trust.json"))
}

func (s *Service) handleArtifactByHash(w http.ResponseWriter, r *http.Request) {
	want := strings.TrimPrefix(r.URL.Path, "/api/v0/artifacts/sha256/")
	if len(want) != 64 {
		http.NotFound(w, r)
		return
	}
	releases, err := s.publishedReleases()
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	for _, rel := range releases {
		dir := s.releaseDir(rel.Publisher, rel.Name, rel.Version)
		found := ""
		_ = filepath.WalkDir(dir, func(path string, d os.DirEntry, err error) error {
			if err != nil || d.IsDir() || found != "" {
				return nil
			}
			body, err := os.ReadFile(path)
			if err == nil && sha256Hex(body) == want {
				found = path
			}
			return nil
		})
		if found != "" {
			http.ServeFile(w, r, found)
			return
		}
	}
	http.NotFound(w, r)
}

func (s *Service) publishedReleases() ([]ReleaseMeta, error) {
	root := filepath.Join(s.dataDir, "packages")
	var out []ReleaseMeta
	err := filepath.WalkDir(root, func(path string, d os.DirEntry, err error) error {
		if err != nil || d.IsDir() || filepath.Base(path) != "release.json" {
			return nil
		}
		rel, err := readJSONFile[ReleaseMeta](path)
		if err == nil && rel.Status == "published" {
			out = append(out, rel)
		}
		return nil
	})
	if errors.Is(err, os.ErrNotExist) {
		return nil, nil
	}
	sort.Slice(out, func(i, j int) bool {
		a := out[i].Publisher + "/" + out[i].Name + "/" + out[i].Version
		b := out[j].Publisher + "/" + out[j].Name + "/" + out[j].Version
		return a < b
	})
	return out, err
}

func (s *Service) requireAdmin(w http.ResponseWriter, r *http.Request) bool {
	if s.adminPassword == "" && len(s.adminTokenHash) == 0 {
		http.Error(w, "admin auth is not configured", http.StatusServiceUnavailable)
		return false
	}
	if s.adminAuthorized(r) {
		return true
	}
	w.Header().Set("WWW-Authenticate", `Basic realm="obc-store"`)
	http.Error(w, "unauthorized", http.StatusUnauthorized)
	return false
}

func (s *Service) requirePublisher(w http.ResponseWriter, r *http.Request, publisherID string) bool {
	if s.adminAuthorized(r) || s.publisherAuthorized(publisherID, r) {
		return true
	}
	http.Error(w, "unauthorized", http.StatusUnauthorized)
	return false
}

func (s *Service) adminAuthorized(r *http.Request) bool {
	if len(s.adminTokenHash) > 0 && strings.HasPrefix(r.Header.Get("Authorization"), "Bearer ") {
		token := strings.TrimSpace(strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer "))
		sum := sha256.Sum256([]byte(token))
		if subtle.ConstantTimeCompare(sum[:], s.adminTokenHash) == 1 {
			return true
		}
		return false
	}
	u, p, ok := r.BasicAuth()
	if !ok || s.adminUser == "" || s.adminPassword == "" || constantTimeStringEqual(u, s.adminUser) != 1 || constantTimeStringEqual(p, s.adminPassword) != 1 {
		return false
	}
	return true
}

func (s *Service) publisherAuthorized(publisherID string, r *http.Request) bool {
	if !safeID(publisherID) || !strings.HasPrefix(r.Header.Get("Authorization"), "Bearer ") {
		return false
	}
	publisher, err := readJSONFile[Publisher](s.publisherPath(publisherID))
	if err != nil || publisher.TokenSHA256Hex == "" {
		return false
	}
	want, err := hex.DecodeString(strings.TrimSpace(publisher.TokenSHA256Hex))
	if err != nil || len(want) != sha256.Size {
		return false
	}
	token := strings.TrimSpace(strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer "))
	sum := sha256.Sum256([]byte(token))
	return subtle.ConstantTimeCompare(sum[:], want) == 1
}

func constantTimeStringEqual(a, b string) int {
	if len(a) != len(b) {
		return 0
	}
	return subtle.ConstantTimeCompare([]byte(a), []byte(b))
}

func (s *Service) publisherPath(id string) string {
	return filepath.Join(s.dataDir, "publishers", id+".json")
}

func (s *Service) packageDir(pub, name string) string {
	return filepath.Join(s.dataDir, "packages", pub, name)
}

func (s *Service) packageMetaPath(pub, name string) string {
	return filepath.Join(s.packageDir(pub, name), "package.json")
}

func (s *Service) releaseDir(pub, name, version string) string {
	return filepath.Join(s.packageDir(pub, name), version)
}

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

func renderHTML(w http.ResponseWriter, tmpl *template.Template, data any) {
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.WriteHeader(http.StatusOK)
	_ = tmpl.Execute(w, data)
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

func marshalJSON(v any) ([]byte, error) {
	body, err := json.MarshalIndent(v, "", "  ")
	if err != nil {
		return nil, err
	}
	return append(body, '\n'), nil
}

func sha256Hex(body []byte) string {
	sum := sha256.Sum256(body)
	return hex.EncodeToString(sum[:])
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

const siteCSS = `
body{margin:0;background:#f5f1e8;color:#1c1913;font:16px/1.5 Georgia,"Times New Roman",serif}
a{color:#146c5b;text-decoration:none}a:hover{text-decoration:underline}
header{background:linear-gradient(135deg,#17211f,#36584d);color:#fff;padding:36px 22px}
main{max-width:980px;margin:0 auto;padding:24px}
.brand{font-size:38px;letter-spacing:-1px;margin:0 0 8px}
.muted{color:#675f50}.pill{display:inline-block;border:1px solid #d7cdbb;border-radius:999px;padding:2px 9px;margin:2px;background:#fff8ec}
.card{background:#fffaf0;border:1px solid #ded3bd;border-radius:18px;padding:18px;margin:14px 0;box-shadow:0 8px 24px #00000012}
input{font:inherit;padding:10px;border:1px solid #cbbfa8;border-radius:10px;background:#fff}
button{font:inherit;padding:10px 14px;border:0;border-radius:10px;background:#146c5b;color:white}
code,pre{background:#eee3d0;border-radius:8px;padding:2px 5px}pre{overflow:auto;padding:14px}
table{width:100%;border-collapse:collapse}td,th{border-bottom:1px solid #e2d7c3;padding:8px;text-align:left}
@media(max-width:680px){.brand{font-size:30px}main{padding:16px}input,button{width:100%;margin-top:8px}}
`

const siteHomeHTML = `<!doctype html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>OBC Store</title><style>` + siteCSS + `</style></head>
<body><header><h1 class="brand">OBC Store</h1><p>Signed Oren bytecode packages for AVM host apps.</p></header>
<main>
<form class="card" action="/" method="get">
  <input name="query" placeholder="Search packages" value="{{.Query}}">
  <input name="tag" placeholder="Tag" value="{{.Tag}}">
  <input name="capability" placeholder="Capability, e.g. GFX" value="{{.Capability}}">
  <button type="submit">Search</button>
</form>
<p><a href="/api/v0/index.json">index.json</a> · <a href="/api/v0/trust/bundle.json">trust bundle</a> · <a href="/ops">operator guide</a></p>
{{if .Packages}}{{range .Packages}}
<article class="card">
  <h2><a href="/packages/{{.Publisher}}/{{.Name}}">{{if .Title}}{{.Title}}{{else}}{{.ID}}{{end}}</a></h2>
  <p class="muted">{{.ID}}@{{.Version}}</p>
  <p>{{.Summary}}</p>
  <p>{{range .Tags}}<span class="pill">{{.}}</span>{{end}}</p>
</article>
{{end}}{{else}}<div class="card">No published OBC packages match this query.</div>{{end}}
</main></body></html>`

const sitePackageHTML = `<!doctype html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>{{.Meta.Publisher}}/{{.Meta.Name}} - OBC Store</title><style>` + siteCSS + `</style></head>
<body><header><h1 class="brand">{{if .Meta.Title}}{{.Meta.Title}}{{else}}{{.Meta.Publisher}}/{{.Meta.Name}}{{end}}</h1><p>{{.Meta.Summary}}</p></header>
<main>
<p><a href="/">Browse packages</a></p>
<section class="card">
  <h2>Releases</h2>
  {{if .Releases}}<table><tr><th>Version</th><th>Manifest</th><th>Program</th><th>Status</th></tr>
  {{range .Releases}}<tr>
    <td>{{.Version}}</td>
    <td><a href="/api/v0/packages/{{.Publisher}}/{{.Name}}/versions/{{.Version}}/package.json">package.json</a></td>
    <td><a href="/api/v0/packages/{{.Publisher}}/{{.Name}}/versions/{{.Version}}/program.obc">program.obc</a></td>
    <td>{{.Status}}</td>
  </tr>{{end}}</table>{{else}}No published releases.{{end}}
</section>
<section class="card"><h2>Install Metadata</h2><pre>package={{.Meta.Publisher}}/{{.Meta.Name}}
index=https://store.hubstack.cn/api/v0/index.json</pre></section>
</main></body></html>`

const siteOpsHTML = `<!doctype html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>OBC Store Operator Guide</title><style>` + siteCSS + `</style></head>
<body><header><h1 class="brand">Operator Guide</h1><p>Minimal publish and token lifecycle reference.</p></header>
<main>
<section class="card"><h2>Public endpoints</h2><pre>GET /api/v0/health
GET /api/v0/index.json
GET /api/v0/index.json.sig
GET /api/v0/packages?query=plot&amp;capability=GFX</pre></section>
<section class="card"><h2>Publisher token lifecycle</h2><pre>POST   /api/v0/publishers/{publisher}/token
DELETE /api/v0/publishers/{publisher}/token
Authorization: Bearer &lt;current publisher token or admin token&gt;
Body: {"token_sha256_hex":"&lt;sha256 hex of new token&gt;"}</pre></section>
<section class="card"><h2>Publish flow</h2><pre>POST /api/v0/packages
POST /api/v0/packages/{publisher}/{name}/versions
POST /api/v0/packages/{publisher}/{name}/versions/{version}/publish</pre></section>
</main></body></html>`

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
