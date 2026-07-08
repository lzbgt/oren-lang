package obcstore

import (
	"errors"
	"os"
	"path/filepath"
	"strings"
	"time"
)

type OperatorStatus struct {
	Schema                 string   `json:"schema"`
	Service                string   `json:"service"`
	BuildCommit            string   `json:"build_commit"`
	BuildTime              string   `json:"build_time,omitempty"`
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
	ReadyReleaseCount      int      `json:"ready_release_count"`
	IncompleteReleaseCount int      `json:"incomplete_release_count"`
	MissingBundleCount     int      `json:"missing_bundle_count"`
	MissingSignatureCount  int      `json:"missing_signature_count"`
	MissingSourceCount     int      `json:"missing_source_count"`
	MissingPermissionCount int      `json:"missing_permission_count"`
	SignedIndexEnabled     bool     `json:"signed_index_enabled"`
	IndexSigningKeyID      string   `json:"index_signing_key_id,omitempty"`
	IndexSigningKeyTrusted bool     `json:"index_signing_key_trusted"`
	TrustBundleAvailable   bool     `json:"trust_bundle_available"`
	TrustBundleStoreKeys   int      `json:"trust_bundle_store_keys"`
	TrustBundleStoreKeyIDs []string `json:"trust_bundle_store_key_ids,omitempty"`
	AuditEventCount        int      `json:"audit_event_count"`
	AdminAuthConfigured    bool     `json:"admin_auth_configured"`
	DataDirWritable        bool     `json:"data_dir_writable"`
	DataDirFileCount       int      `json:"data_dir_file_count"`
	DataDirBytes           int64    `json:"data_dir_bytes"`
	MetadataBytes          int64    `json:"metadata_bytes"`
	PayloadBytes           int64    `json:"payload_bytes"`
	ProgramBytes           int64    `json:"program_bytes"`
	BundleBytes            int64    `json:"bundle_bytes"`
	AssetBytes             int64    `json:"asset_bytes"`
	ScreenshotBytes        int64    `json:"screenshot_bytes"`
	AuditLogBytes          int64    `json:"audit_log_bytes"`
}

func (s *Service) operatorStatus() (OperatorStatus, error) {
	status := OperatorStatus{
		Schema:              indexSchema,
		Service:             "obc-store",
		BuildCommit:         BuildCommit,
		BuildTime:           BuildTime,
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
	auditCount, err := s.auditEventCount()
	if err != nil {
		return status, err
	}
	status.AuditEventCount = auditCount
	if err := s.addOperatorStorageStatus(&status); err != nil {
		return status, err
	}
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
		manifest, manifestErr := readJSONFile[map[string]any](filepath.Join(s.releaseDir(rel.Publisher, rel.Name, rel.Version), "package.json"))
		if manifestErr == nil {
			sources := sourceLinksFromManifest(rel.Publisher, rel.Name, rel.Version, manifest)
			if len(sources) > 0 {
				status.SourceReleaseCount++
				status.SourceAssetCount += len(sources)
			}
			if defaults, ok := manifest["permission_defaults"].([]any); ok {
				status.PermissionDefaultCount += len(defaults)
			}
		}
		_, missingReadiness := releaseReadiness(rel, manifest)
		if len(missingReadiness) == 0 {
			status.ReadyReleaseCount++
		} else {
			status.IncompleteReleaseCount++
			for _, missing := range missingReadiness {
				switch missing {
				case "bundle":
					status.MissingBundleCount++
				case "signature":
					status.MissingSignatureCount++
				case "source":
					status.MissingSourceCount++
				case "permissions":
					status.MissingPermissionCount++
				}
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

func (s *Service) addOperatorStorageStatus(status *OperatorStatus) error {
	status.DataDirWritable = dataDirWritable(s.dataDir)
	err := filepath.WalkDir(s.dataDir, func(path string, d os.DirEntry, err error) error {
		if err != nil || d.IsDir() {
			return nil
		}
		info, infoErr := d.Info()
		if infoErr != nil {
			return nil
		}
		size := info.Size()
		status.DataDirFileCount++
		status.DataDirBytes += size
		rel, relErr := filepath.Rel(s.dataDir, path)
		if relErr != nil {
			return nil
		}
		switch operatorStorageKind(filepath.ToSlash(rel)) {
		case "audit":
			status.AuditLogBytes += size
			status.MetadataBytes += size
		case "metadata":
			status.MetadataBytes += size
		case "program":
			status.ProgramBytes += size
			status.PayloadBytes += size
		case "bundle":
			status.BundleBytes += size
			status.PayloadBytes += size
		case "asset":
			status.AssetBytes += size
			status.PayloadBytes += size
		case "screenshot":
			status.ScreenshotBytes += size
			status.PayloadBytes += size
		default:
			status.PayloadBytes += size
		}
		return nil
	})
	if errors.Is(err, os.ErrNotExist) {
		return nil
	}
	return err
}

func dataDirWritable(dir string) bool {
	file, err := os.CreateTemp(dir, ".obc-store-write-probe-*")
	if err != nil {
		return false
	}
	name := file.Name()
	if err := file.Close(); err != nil {
		_ = os.Remove(name)
		return false
	}
	return os.Remove(name) == nil
}

func operatorStorageKind(rel string) string {
	base := filepath.Base(rel)
	switch {
	case rel == "audit/audit.log.jsonl":
		return "audit"
	case strings.HasSuffix(base, ".json") || strings.HasSuffix(base, ".sig"):
		return "metadata"
	case base == "program.obc":
		return "program"
	case base == "bundle.obc.zip":
		return "bundle"
	case strings.Contains(rel, "/screenshots/"):
		return "screenshot"
	case strings.Contains(rel, "/assets/"):
		return "asset"
	default:
		return "payload"
	}
}
