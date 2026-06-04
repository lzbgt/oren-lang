package obcstore

import (
	"errors"
	"net/http"
	"os"
	"path/filepath"
	"sort"
)

type OperatorReleaseItem struct {
	Publisher        string   `json:"publisher"`
	Name             string   `json:"name"`
	Title            string   `json:"title,omitempty"`
	Version          string   `json:"version"`
	Status           string   `json:"status"`
	Visibility       string   `json:"visibility"`
	LatestPublished  bool     `json:"latest_published"`
	UpdatedAt        string   `json:"updated_at,omitempty"`
	Readiness        []string `json:"readiness"`
	MissingReadiness []string `json:"missing_readiness"`
	PackageURL       string   `json:"package_url"`
	PublishURL       string   `json:"publish_url"`
	YankURL          string   `json:"yank_url"`
	VisibilityURL    string   `json:"visibility_url"`
}

type OperatorReleaseInventory struct {
	Schema    string                `json:"schema"`
	Service   string                `json:"service"`
	Releases  []OperatorReleaseItem `json:"releases"`
	Generated string                `json:"generated_at"`
}

func (s *Service) handleSiteOpsReleases(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path != "/ops/releases" {
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
	inventory, err := s.operatorReleaseInventory()
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	renderHTML(w, siteOpsReleasesTemplate, inventory)
}

func (s *Service) handleOpsReleases(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	if !s.requireAdmin(w, r) {
		return
	}
	inventory, err := s.operatorReleaseInventory()
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	writeJSON(w, http.StatusOK, inventory)
}

func (s *Service) operatorReleaseInventory() (OperatorReleaseInventory, error) {
	items, err := s.operatorReleaseItems()
	if err != nil {
		return OperatorReleaseInventory{}, err
	}
	return OperatorReleaseInventory{
		Schema:    "oren.obc.store.ops.releases.v0",
		Service:   "obc-store",
		Generated: s.now().UTC().Format("2006-01-02T15:04:05Z07:00"),
		Releases:  items,
	}, nil
}

func (s *Service) operatorReleaseItems() ([]OperatorReleaseItem, error) {
	root := filepath.Join(s.dataDir, "packages")
	packages, err := s.allPackageMeta()
	if err != nil {
		return nil, err
	}
	var items []OperatorReleaseItem
	err = filepath.WalkDir(root, func(path string, d os.DirEntry, err error) error {
		if err != nil || d.IsDir() || filepath.Base(path) != "release.json" {
			return nil
		}
		rel, err := readJSONFile[ReleaseMeta](path)
		if err != nil {
			return nil
		}
		key := rel.Publisher + "/" + rel.Name
		meta := packages[key]
		item := s.operatorReleaseItem(meta, rel)
		items = append(items, item)
		return nil
	})
	if errors.Is(err, os.ErrNotExist) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	latest := latestPublishedByPackage(items)
	for i := range items {
		items[i].LatestPublished = items[i].Status == "published" && items[i].Version == latest[items[i].Publisher+"/"+items[i].Name]
	}
	sort.Slice(items, func(i, j int) bool {
		a := items[i].Publisher + "/" + items[i].Name + "/" + items[i].Version
		b := items[j].Publisher + "/" + items[j].Name + "/" + items[j].Version
		return a < b
	})
	return items, nil
}

func (s *Service) allPackageMeta() (map[string]PackageMeta, error) {
	root := filepath.Join(s.dataDir, "packages")
	out := map[string]PackageMeta{}
	err := filepath.WalkDir(root, func(path string, d os.DirEntry, err error) error {
		if err != nil || d.IsDir() || filepath.Base(path) != "package.json" {
			return nil
		}
		meta, err := readJSONFile[PackageMeta](path)
		if err == nil && meta.Publisher != "" && meta.Name != "" && path == s.packageMetaPath(meta.Publisher, meta.Name) {
			out[meta.Publisher+"/"+meta.Name] = meta
		}
		return nil
	})
	if errors.Is(err, os.ErrNotExist) {
		return out, nil
	}
	return out, err
}

func (s *Service) operatorReleaseItem(meta PackageMeta, rel ReleaseMeta) OperatorReleaseItem {
	manifest, _ := readJSONFile[map[string]any](filepath.Join(s.releaseDir(rel.Publisher, rel.Name, rel.Version), "package.json"))
	readiness, missing := releaseReadiness(rel, manifest)
	return OperatorReleaseItem{
		Publisher:        rel.Publisher,
		Name:             rel.Name,
		Title:            meta.Title,
		Version:          rel.Version,
		Status:           rel.Status,
		Visibility:       normalizeVisibility(meta.Visibility),
		UpdatedAt:        rel.UpdatedAt.UTC().Format("2006-01-02T15:04:05Z07:00"),
		Readiness:        readiness,
		MissingReadiness: missing,
		PackageURL:       "/packages/" + rel.Publisher + "/" + rel.Name,
		PublishURL:       "/api/v0/packages/" + rel.Publisher + "/" + rel.Name + "/versions/" + rel.Version + "/publish",
		YankURL:          "/api/v0/packages/" + rel.Publisher + "/" + rel.Name + "/versions/" + rel.Version + "/yank",
		VisibilityURL:    "/api/v0/packages/" + rel.Publisher + "/" + rel.Name + "/visibility",
	}
}

func releaseReadiness(rel ReleaseMeta, manifest map[string]any) ([]string, []string) {
	var ok []string
	var missing []string
	if rel.BundlePath != "" && rel.BundleSHA256 != "" {
		ok = append(ok, "bundle")
	} else {
		missing = append(missing, "bundle")
	}
	if rel.SignatureAlg != "" && rel.SignatureP256SHA256DERHex != "" {
		ok = append(ok, "signature")
	} else {
		missing = append(missing, "signature")
	}
	if len(sourceLinksFromManifest(rel.Publisher, rel.Name, rel.Version, manifest)) > 0 {
		ok = append(ok, "source")
	} else {
		missing = append(missing, "source")
	}
	if defaults, _ := manifest["permission_defaults"].([]any); len(defaults) > 0 {
		ok = append(ok, "permissions")
	} else {
		missing = append(missing, "permissions")
	}
	return ok, missing
}

func latestPublishedByPackage(items []OperatorReleaseItem) map[string]string {
	out := map[string]string{}
	for _, item := range items {
		if item.Status != "published" {
			continue
		}
		key := item.Publisher + "/" + item.Name
		if out[key] == "" || compareVersions(item.Version, out[key]) > 0 {
			out[key] = item.Version
		}
	}
	return out
}
