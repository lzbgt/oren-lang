package obcstore

import (
	"archive/zip"
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
	indexSchema            = "oren.obc.store.index.v0"
	manifestSchema         = "oren.obc.package.v0"
	releaseBundleMediaType = "application/vnd.oren.obc.release+zip"
)

type Config struct {
	DataDir                string
	AdminUser              string
	AdminPassword          string
	AdminTokenSHA256Hex    string
	IndexSigningKeyPEMPath string
	IndexSigningKeyID      string
	TrustBundlePath        string
	Now                    func() time.Time
}

type Service struct {
	dataDir           string
	adminUser         string
	adminPassword     string
	adminTokenHash    []byte
	indexSigner       *ecdsa.PrivateKey
	indexSigningKeyID string
	trustBundlePath   string
	now               func() time.Time
	mu                sync.Mutex
}

type Publisher struct {
	ID             string   `json:"id"`
	DisplayName    string   `json:"display_name,omitempty"`
	PublicKeys     []string `json:"public_keys,omitempty"`
	TokenSHA256Hex string   `json:"token_sha256_hex,omitempty"`
	Status         string   `json:"status,omitempty"`
}

type PackageMeta struct {
	Publisher  string   `json:"publisher"`
	Name       string   `json:"name"`
	Title      string   `json:"title,omitempty"`
	Summary    string   `json:"summary,omitempty"`
	Tags       []string `json:"tags,omitempty"`
	Status     string   `json:"status,omitempty"`
	Visibility string   `json:"visibility,omitempty"`
}

type PackageListItem struct {
	ID            string   `json:"id"`
	Publisher     string   `json:"publisher"`
	Name          string   `json:"name"`
	Version       string   `json:"version"`
	Title         string   `json:"title,omitempty"`
	Summary       string   `json:"summary,omitempty"`
	Tags          []string `json:"tags,omitempty"`
	ScreenshotURL string   `json:"screenshot_url,omitempty"`
}

type SiteSourceLink struct {
	Path     string
	Language string
	Role     string
	URL      string
}

type SiteRelease struct {
	ReleaseMeta
	Capabilities            []string
	Sources                 []SiteSourceLink
	Screenshots             []SiteSourceLink
	PermissionDefaultsCount int
}

type AssetUpload struct {
	Path          string `json:"path"`
	MediaType     string `json:"media_type,omitempty"`
	ContentBase64 string `json:"content_base64"`
}

type ScreenshotUpload struct {
	Path          string `json:"path,omitempty"`
	MediaType     string `json:"media_type,omitempty"`
	ContentBase64 string `json:"content_base64"`
}

type ReleaseUpload struct {
	Version                   string                 `json:"version"`
	Manifest                  map[string]any         `json:"manifest,omitempty"`
	ProgramOBCBase64          string                 `json:"program_obc_base64"`
	ReleaseBundleBase64       string                 `json:"release_bundle_base64,omitempty"`
	Assets                    []AssetUpload          `json:"assets,omitempty"`
	Screenshots               []ScreenshotUpload     `json:"screenshots,omitempty"`
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

type PackageVisibilityUpdate struct {
	Visibility string `json:"visibility"`
}

type OperatorStatus struct {
	Schema                 string   `json:"schema"`
	Service                string   `json:"service"`
	GeneratedAt            string   `json:"generated_at"`
	PublisherCount         int      `json:"publisher_count"`
	ActivePublisherCount   int      `json:"active_publisher_count"`
	DisabledPublisherCount int      `json:"disabled_publisher_count"`
	PackageCount           int      `json:"package_count"`
	PublicPackageCount     int      `json:"public_package_count"`
	PrivatePackageCount    int      `json:"private_package_count"`
	ReleaseCount           int      `json:"release_count"`
	PublishedReleaseCount  int      `json:"published_release_count"`
	YankedReleaseCount     int      `json:"yanked_release_count"`
	DraftReleaseCount      int      `json:"draft_release_count"`
	BundleReleaseCount     int      `json:"bundle_release_count"`
	SignedReleaseCount     int      `json:"signed_release_count"`
	SourceReleaseCount     int      `json:"source_release_count"`
	SourceAssetCount       int      `json:"source_asset_count"`
	PermissionDefaultCount int      `json:"permission_default_count"`
	SignedIndexEnabled     bool     `json:"signed_index_enabled"`
	IndexSigningKeyID      string   `json:"index_signing_key_id,omitempty"`
	IndexSigningKeyTrusted bool     `json:"index_signing_key_trusted"`
	TrustBundleAvailable   bool     `json:"trust_bundle_available"`
	TrustBundleStoreKeys   int      `json:"trust_bundle_store_keys"`
	TrustBundleStoreKeyIDs []string `json:"trust_bundle_store_key_ids,omitempty"`
	AdminAuthConfigured    bool     `json:"admin_auth_configured"`
}

type ReleaseMeta struct {
	Publisher                 string    `json:"publisher"`
	Name                      string    `json:"name"`
	Version                   string    `json:"version"`
	Status                    string    `json:"status"`
	ManifestPath              string    `json:"manifest"`
	ManifestSHA256            string    `json:"manifest_sha256"`
	OBCSHA256                 string    `json:"obc_sha256"`
	BundlePath                string    `json:"bundle,omitempty"`
	BundleSHA256              string    `json:"bundle_sha256,omitempty"`
	BundleMediaType           string    `json:"bundle_media_type,omitempty"`
	SignatureAlg              string    `json:"signature_alg,omitempty"`
	SignatureP256SHA256DERHex string    `json:"signature_p256_sha256_der_hex,omitempty"`
	Tags                      []string  `json:"tags,omitempty"`
	MinApp                    string    `json:"min_app,omitempty"`
	Screenshots               []string  `json:"screenshots,omitempty"`
	CreatedAt                 time.Time `json:"created_at"`
	UpdatedAt                 time.Time `json:"updated_at"`
}

type ReleasePublishRequest struct {
	SignatureAlg              string `json:"signature_alg,omitempty"`
	SignatureP256SHA256DERHex string `json:"signature_p256_sha256_der_hex,omitempty"`
}

type trustBundleFile struct {
	Schema    string          `json:"schema"`
	StoreKeys []trustStoreKey `json:"store_keys"`
}

type trustStoreKey struct {
	ID               string `json:"id"`
	Alg              string `json:"alg"`
	PublicKeyX963B64 string `json:"public_key_x963_b64"`
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
	indexSigningKeyID := strings.TrimSpace(cfg.IndexSigningKeyID)
	if cfg.IndexSigningKeyPEMPath != "" {
		key, err := loadP256PrivateKey(cfg.IndexSigningKeyPEMPath)
		if err != nil {
			return nil, err
		}
		indexSigner = key
		if indexSigningKeyID == "" {
			indexSigningKeyID = derivedP256KeyID(&key.PublicKey)
		}
	}
	if indexSigner == nil && indexSigningKeyID != "" {
		return nil, errors.New("index signing key id requires an index signing key")
	}
	if indexSigningKeyID != "" && !safeID(indexSigningKeyID) {
		return nil, errors.New("index signing key id must contain only letters, digits, '_', '.', or '-'")
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
		dataDir:           cfg.DataDir,
		adminUser:         cfg.AdminUser,
		adminPassword:     cfg.AdminPassword,
		adminTokenHash:    adminTokenHash,
		indexSigner:       indexSigner,
		indexSigningKeyID: indexSigningKeyID,
		trustBundlePath:   strings.TrimSpace(cfg.TrustBundlePath),
		now:               now,
	}, nil
}

func (s *Service) Handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("/", s.handleSiteHome)
	mux.HandleFunc("/healthz", s.handleHealth)
	mux.HandleFunc("/ops", s.handleSiteOps)
	mux.HandleFunc("/ops/status", s.handleSiteOpsStatus)
	mux.HandleFunc("/publishers/", s.handleSitePublisher)
	mux.HandleFunc("/packages/", s.handleSitePackage)
	mux.HandleFunc("/api/v0/health", s.handleHealth)
	mux.HandleFunc("/api/v0/me", s.handleMe)
	mux.HandleFunc("/api/v0/ops/status", s.handleOpsStatus)
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

func (s *Service) handleHealth(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet && r.Method != http.MethodHead {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"status":  "ok",
		"schema":  indexSchema,
		"service": "obc-store",
	})
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

func (s *Service) handleSitePublisher(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	publisherID := strings.TrimPrefix(r.URL.Path, "/publishers/")
	if !safeID(publisherID) {
		http.NotFound(w, r)
		return
	}
	publisher, err := readJSONFile[Publisher](s.publisherPath(publisherID))
	if err != nil || publisher.Status == "disabled" {
		http.NotFound(w, r)
		return
	}
	items, err := s.packageItemsForPublisher(publisherID)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	renderHTML(w, sitePublisherTemplate, map[string]any{
		"Publisher": publisher,
		"Packages":  items,
	})
}

func (s *Service) handleSitePackage(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	rest := strings.TrimPrefix(r.URL.Path, "/packages/")
	parts := strings.Split(rest, "/")
	if (len(parts) != 2 && len(parts) != 3) || !safeID(parts[0]) || !safeID(parts[1]) {
		http.NotFound(w, r)
		return
	}
	pub, name := parts[0], parts[1]
	if len(parts) == 3 {
		if parts[2] != "source" {
			http.NotFound(w, r)
			return
		}
		s.handleSiteSource(w, r, pub, name)
		return
	}
	meta, err := readJSONFile[PackageMeta](s.packageMetaPath(pub, name))
	if err != nil {
		http.NotFound(w, r)
		return
	}
	if !packageIsPublic(meta) {
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
	siteReleases := s.siteReleaseItems(pub, name, published)
	renderHTML(w, sitePackageTemplate, map[string]any{
		"Meta":     meta,
		"Releases": siteReleases,
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

func (s *Service) handleSiteOpsStatus(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path != "/ops/status" {
		http.NotFound(w, r)
		return
	}
	if r.Method != http.MethodGet {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	if !s.requireAdmin(w, r) {
		return
	}
	status, err := s.operatorStatus()
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	renderHTML(w, siteOpsStatusTemplate, status)
}

func (s *Service) handleOpsStatus(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	if !s.requireAdmin(w, r) {
		return
	}
	status, err := s.operatorStatus()
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	writeJSON(w, http.StatusOK, status)
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
		s.getPackage(w, r, pub, name)
		return
	}
	if parts[2] == "visibility" {
		if len(parts) != 3 {
			http.NotFound(w, r)
			return
		}
		if r.Method != http.MethodPost && r.Method != http.MethodPut {
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			return
		}
		if !s.requirePublisher(w, r, pub) {
			return
		}
		s.setPackageVisibility(w, r, pub, name)
		return
	}
	if parts[2] != "versions" {
		http.NotFound(w, r)
		return
	}
	if len(parts) == 3 {
		if r.Method == http.MethodGet {
			s.listVersions(w, r, pub, name)
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
		s.getRelease(w, r, pub, name, version)
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
	p.Visibility = normalizeVisibility(p.Visibility)
	if !validVisibility(p.Visibility) {
		http.Error(w, "invalid package visibility", http.StatusBadRequest)
		return
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

func (s *Service) setPackageVisibility(w http.ResponseWriter, r *http.Request, pub, name string) {
	var update PackageVisibilityUpdate
	if !decodeJSON(w, r, &update) {
		return
	}
	visibility := normalizeVisibility(update.Visibility)
	if !validVisibility(visibility) {
		http.Error(w, "invalid package visibility", http.StatusBadRequest)
		return
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	path := s.packageMetaPath(pub, name)
	meta, err := readJSONFile[PackageMeta](path)
	if err != nil {
		http.Error(w, "package not found", http.StatusNotFound)
		return
	}
	meta.Visibility = visibility
	if err := writeJSONFile(path, meta); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	writeJSON(w, http.StatusOK, meta)
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
	var bundle []byte
	if upload.ReleaseBundleBase64 != "" {
		bundle, err = base64.StdEncoding.DecodeString(upload.ReleaseBundleBase64)
		if err != nil {
			http.Error(w, "invalid release_bundle_base64", http.StatusBadRequest)
			return
		}
		if err := validateReleaseBundleZIP(bundle); err != nil {
			http.Error(w, "invalid release bundle: "+err.Error(), http.StatusBadRequest)
			return
		}
	}
	if err := validateManifestPermissionDefaults(upload.Manifest); err != nil {
		http.Error(w, "invalid manifest permission_defaults: "+err.Error(), http.StatusBadRequest)
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
	var bundleHash string
	if len(bundle) > 0 {
		if err := os.WriteFile(filepath.Join(dir, "bundle.obc.zip"), bundle, 0o644); err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		bundleHash = sha256Hex(bundle)
	}
	assetEntries, ok := s.writeAssets(w, dir, upload.Assets)
	if !ok {
		return
	}
	screenshots, ok := s.writeScreenshots(w, dir, upload.Screenshots)
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
		Screenshots:               screenshots,
		CreatedAt:                 now,
		UpdatedAt:                 now,
	}
	if bundleHash != "" {
		rel.BundlePath = fmt.Sprintf("packages/%s/%s/versions/%s/bundle.obc.zip", pub, name, upload.Version)
		rel.BundleSHA256 = bundleHash
		rel.BundleMediaType = releaseBundleMediaType
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
		if !safeRelPath(asset.Path) || !strings.HasPrefix(asset.Path, "assets/") || asset.ContentBase64 == "" {
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

func (s *Service) writeScreenshots(w http.ResponseWriter, dir string, screenshots []ScreenshotUpload) ([]string, bool) {
	out := make([]string, 0, len(screenshots))
	for i, shot := range screenshots {
		if shot.ContentBase64 == "" {
			http.Error(w, "invalid screenshot upload", http.StatusBadRequest)
			return nil, false
		}
		mediaType := shot.MediaType
		if mediaType == "" {
			mediaType = "image/png"
		}
		if !strings.HasPrefix(mediaType, "image/") {
			http.Error(w, "invalid screenshot media_type", http.StatusBadRequest)
			return nil, false
		}
		rel := shot.Path
		if rel == "" {
			rel = fmt.Sprintf("screenshots/preview-%d.png", i+1)
		}
		if !strings.HasPrefix(rel, "screenshots/") {
			rel = "screenshots/" + rel
		}
		if !safeRelPath(rel) {
			http.Error(w, "invalid screenshot path", http.StatusBadRequest)
			return nil, false
		}
		body, err := base64.StdEncoding.DecodeString(shot.ContentBase64)
		if err != nil {
			http.Error(w, "invalid screenshot content_base64", http.StatusBadRequest)
			return nil, false
		}
		target := filepath.Join(dir, filepath.FromSlash(rel))
		if err := os.MkdirAll(filepath.Dir(target), 0o755); err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return nil, false
		}
		if err := os.WriteFile(target, body, 0o644); err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return nil, false
		}
		out = append(out, filepath.ToSlash(rel))
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
		items = append(items, s.packageListItem(rel, meta))
		if len(items) >= limit {
			break
		}
	}
	return items, nil
}

func (s *Service) packageItemsForPublisher(publisherID string) ([]PackageListItem, error) {
	releases, err := s.publishedReleases()
	if err != nil {
		return nil, err
	}
	items := make([]PackageListItem, 0)
	for _, rel := range releases {
		if rel.Publisher != publisherID {
			continue
		}
		meta, _ := readJSONFile[PackageMeta](s.packageMetaPath(rel.Publisher, rel.Name))
		items = append(items, s.packageListItem(rel, meta))
	}
	return items, nil
}

func (s *Service) packageListItem(rel ReleaseMeta, meta PackageMeta) PackageListItem {
	item := PackageListItem{
		ID:        rel.Publisher + "/" + rel.Name,
		Publisher: rel.Publisher,
		Name:      rel.Name,
		Version:   rel.Version,
		Title:     meta.Title,
		Summary:   meta.Summary,
		Tags:      append(meta.Tags, rel.Tags...),
	}
	screens := screenshotLinksFromRelease(rel)
	if len(screens) > 0 {
		item.ScreenshotURL = screens[0].URL
	}
	return item
}

func (s *Service) siteReleaseItems(pub, name string, releases []ReleaseMeta) []SiteRelease {
	items := make([]SiteRelease, 0, len(releases))
	for _, rel := range releases {
		item := SiteRelease{ReleaseMeta: rel}
		manifest, err := readJSONFile[map[string]any](filepath.Join(s.releaseDir(pub, name, rel.Version), "package.json"))
		if err == nil {
			item.Capabilities = stringListFromAny(manifest["capabilities"])
			item.Sources = sourceLinksFromManifest(pub, name, rel.Version, manifest)
			if defaults, ok := manifest["permission_defaults"].([]any); ok {
				item.PermissionDefaultsCount = len(defaults)
			}
		}
		item.Screenshots = screenshotLinksFromRelease(rel)
		items = append(items, item)
	}
	return items
}

func stringListFromAny(raw any) []string {
	xs, ok := raw.([]any)
	if !ok {
		return nil
	}
	out := make([]string, 0, len(xs))
	for _, rawItem := range xs {
		if s, ok := rawItem.(string); ok && s != "" {
			out = append(out, s)
		}
	}
	return out
}

func sourceLinksFromManifest(pub, name, version string, manifest map[string]any) []SiteSourceLink {
	rawSources, ok := manifest["sources"].([]any)
	if !ok {
		return nil
	}
	out := make([]SiteSourceLink, 0, len(rawSources))
	for _, raw := range rawSources {
		src, ok := raw.(map[string]any)
		if !ok {
			continue
		}
		path, _ := src["path"].(string)
		if !safeRelPath(path) || !strings.HasPrefix(path, "assets/") {
			continue
		}
		lang, _ := src["language"].(string)
		role, _ := src["role"].(string)
		out = append(out, SiteSourceLink{
			Path:     path,
			Language: lang,
			Role:     role,
			URL:      sourceViewURL(pub, name, version, path),
		})
	}
	return out
}

func screenshotLinksFromRelease(rel ReleaseMeta) []SiteSourceLink {
	out := make([]SiteSourceLink, 0, len(rel.Screenshots))
	for _, path := range rel.Screenshots {
		if !safeRelPath(path) || !strings.HasPrefix(path, "screenshots/") {
			continue
		}
		out = append(out, SiteSourceLink{
			Path: path,
			Role: "screenshot",
			URL:  fmt.Sprintf("/api/v0/packages/%s/%s/versions/%s/%s", rel.Publisher, rel.Name, rel.Version, path),
		})
	}
	return out
}

func (s *Service) getPackage(w http.ResponseWriter, r *http.Request, pub, name string) {
	meta, err := readJSONFile[PackageMeta](s.packageMetaPath(pub, name))
	if err != nil {
		http.NotFound(w, nil)
		return
	}
	if !s.packageVisibleToRequest(meta, r) {
		http.NotFound(w, r)
		return
	}
	writeJSON(w, http.StatusOK, meta)
}

func (s *Service) listVersions(w http.ResponseWriter, r *http.Request, pub, name string) {
	meta, err := readJSONFile[PackageMeta](s.packageMetaPath(pub, name))
	if err != nil {
		http.NotFound(w, nil)
		return
	}
	if !s.packageVisibleToRequest(meta, r) {
		http.NotFound(w, r)
		return
	}
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

func (s *Service) getRelease(w http.ResponseWriter, r *http.Request, pub, name, version string) {
	meta, err := readJSONFile[PackageMeta](s.packageMetaPath(pub, name))
	if err != nil {
		http.NotFound(w, nil)
		return
	}
	if !s.packageVisibleToRequest(meta, r) {
		http.NotFound(w, r)
		return
	}
	rel, err := readJSONFile[ReleaseMeta](filepath.Join(s.releaseDir(pub, name, version), "release.json"))
	if err != nil {
		http.NotFound(w, nil)
		return
	}
	writeJSON(w, http.StatusOK, rel)
}

func (s *Service) downloadReleaseFile(w http.ResponseWriter, r *http.Request, pub, name, version string, tail []string) {
	meta, err := readJSONFile[PackageMeta](s.packageMetaPath(pub, name))
	if err != nil {
		http.NotFound(w, r)
		return
	}
	if !s.packageVisibleToRequest(meta, r) {
		http.NotFound(w, r)
		return
	}
	var rel string
	switch tail[0] {
	case "package.json":
		rel = "package.json"
	case "program.obc":
		rel = "program.obc"
	case "bundle.obc.zip":
		rel = "bundle.obc.zip"
	case "assets":
		if len(tail) < 2 {
			http.NotFound(w, r)
			return
		}
		assetPath := strings.Join(tail[1:], "/")
		rel = "assets/" + assetPath
		if !safeRelPath(rel) || !releaseManifestDeclaresAsset(s.releaseDir(pub, name, version), rel) {
			http.NotFound(w, r)
			return
		}
	case "screenshots":
		if len(tail) < 2 {
			http.NotFound(w, r)
			return
		}
		shotPath := "screenshots/" + strings.Join(tail[1:], "/")
		release, err := readJSONFile[ReleaseMeta](filepath.Join(s.releaseDir(pub, name, version), "release.json"))
		if err != nil || !containsString(release.Screenshots, shotPath) {
			http.NotFound(w, r)
			return
		}
		rel = shotPath
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
		if rel.BundlePath != "" {
			item["bundle"] = rel.BundlePath
			item["bundle_sha256"] = rel.BundleSHA256
			item["bundle_media_type"] = rel.BundleMediaType
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
	w.Header().Set("X-Oren-Signature-Alg", "p256-sha256-der")
	if s.indexSigningKeyID != "" {
		w.Header().Set("X-Oren-Signing-Key-ID", s.indexSigningKeyID)
	}
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write(sig)
}

func (s *Service) handleTrustBundle(w http.ResponseWriter, r *http.Request) {
	http.ServeFile(w, r, s.currentTrustBundlePath())
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
			meta, metaErr := readJSONFile[PackageMeta](s.packageMetaPath(rel.Publisher, rel.Name))
			if metaErr != nil || !packageIsPublic(meta) {
				return nil
			}
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

func (s *Service) operatorStatus() (OperatorStatus, error) {
	status := OperatorStatus{
		Schema:              indexSchema,
		Service:             "obc-store",
		GeneratedAt:         s.now().UTC().Format(time.RFC3339),
		SignedIndexEnabled:  s.indexSigner != nil,
		IndexSigningKeyID:   s.indexSigningKeyID,
		AdminAuthConfigured: s.adminPassword != "" || len(s.adminTokenHash) > 0,
	}
	trustAvailable, trustKeyIDs, err := s.trustBundleStoreKeyIDs()
	if err != nil {
		return status, err
	}
	status.TrustBundleAvailable = trustAvailable
	status.TrustBundleStoreKeyIDs = trustKeyIDs
	status.TrustBundleStoreKeys = len(trustKeyIDs)
	if status.IndexSigningKeyID != "" {
		for _, id := range trustKeyIDs {
			if id == status.IndexSigningKeyID {
				status.IndexSigningKeyTrusted = true
				break
			}
		}
	}
	pubRoot := filepath.Join(s.dataDir, "publishers")
	if err := filepath.WalkDir(pubRoot, func(path string, d os.DirEntry, err error) error {
		if err != nil || d.IsDir() || filepath.Ext(path) != ".json" {
			return nil
		}
		p, readErr := readJSONFile[Publisher](path)
		if readErr != nil {
			return nil
		}
		status.PublisherCount++
		if p.Status == "disabled" {
			status.DisabledPublisherCount++
		} else {
			status.ActivePublisherCount++
		}
		return nil
	}); err != nil && !errors.Is(err, os.ErrNotExist) {
		return status, err
	}
	pkgRoot := filepath.Join(s.dataDir, "packages")
	if err := filepath.WalkDir(pkgRoot, func(path string, d os.DirEntry, err error) error {
		if err != nil || d.IsDir() || filepath.Base(path) != "package.json" {
			return nil
		}
		relPath, relErr := filepath.Rel(pkgRoot, path)
		if relErr != nil || len(strings.Split(filepath.ToSlash(relPath), "/")) != 3 {
			return nil
		}
		meta, readErr := readJSONFile[PackageMeta](path)
		if readErr != nil || meta.Publisher == "" || meta.Name == "" {
			return nil
		}
		status.PackageCount++
		if packageIsPublic(meta) {
			status.PublicPackageCount++
		} else {
			status.PrivatePackageCount++
		}
		return nil
	}); err != nil && !errors.Is(err, os.ErrNotExist) {
		return status, err
	}
	if err := filepath.WalkDir(pkgRoot, func(path string, d os.DirEntry, err error) error {
		if err != nil || d.IsDir() || filepath.Base(path) != "release.json" {
			return nil
		}
		rel, readErr := readJSONFile[ReleaseMeta](path)
		if readErr != nil {
			return nil
		}
		status.ReleaseCount++
		if rel.BundlePath != "" {
			status.BundleReleaseCount++
		}
		if rel.SignatureAlg != "" {
			status.SignedReleaseCount++
		}
		if manifest, manifestErr := readJSONFile[map[string]any](filepath.Join(s.releaseDir(rel.Publisher, rel.Name, rel.Version), "package.json")); manifestErr == nil {
			sources := sourceLinksFromManifest(rel.Publisher, rel.Name, rel.Version, manifest)
			if len(sources) > 0 {
				status.SourceReleaseCount++
				status.SourceAssetCount += len(sources)
			}
			if defaults, ok := manifest["permission_defaults"].([]any); ok {
				status.PermissionDefaultCount += len(defaults)
			}
		}
		switch rel.Status {
		case "published":
			status.PublishedReleaseCount++
		case "yanked":
			status.YankedReleaseCount++
		default:
			status.DraftReleaseCount++
		}
		return nil
	}); err != nil && !errors.Is(err, os.ErrNotExist) {
		return status, err
	}
	return status, nil
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

func (s *Service) packageVisibleToRequest(meta PackageMeta, r *http.Request) bool {
	return packageIsPublic(meta) || s.adminAuthorized(r) || s.publisherAuthorized(meta.Publisher, r)
}

func packageIsPublic(meta PackageMeta) bool {
	return normalizeVisibility(meta.Visibility) == "public"
}

func normalizeVisibility(raw string) string {
	raw = strings.ToLower(strings.TrimSpace(raw))
	if raw == "" {
		return "public"
	}
	return raw
}

func validVisibility(raw string) bool {
	v := normalizeVisibility(raw)
	return v == "public" || v == "private"
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
