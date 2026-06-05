package obcstore

import (
	"errors"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"
)

var (
	errPackageNotFound = errors.New("package not found")
	errReleaseNotFound = errors.New("release not found")
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
	OpsPublishURL    string   `json:"ops_publish_url"`
	OpsYankURL       string   `json:"ops_yank_url"`
	OpsVisibilityURL string   `json:"ops_visibility_url"`
}

type OperatorReleaseInventory struct {
	Schema               string                 `json:"schema"`
	Service              string                 `json:"service"`
	Filters              OperatorReleaseFilters `json:"filters"`
	TotalReleaseCount    int                    `json:"total_release_count"`
	FilteredReleaseCount int                    `json:"filtered_release_count"`
	Releases             []OperatorReleaseItem  `json:"releases"`
	Generated            string                 `json:"generated_at"`
}

type OperatorReleaseFilters struct {
	Status     string `json:"status"`
	Visibility string `json:"visibility"`
	Readiness  string `json:"readiness"`
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
	filters, err := operatorReleaseFiltersFromQuery(r.URL.Query())
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	inventory, err := s.operatorReleaseInventory(filters)
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
	filters, err := operatorReleaseFiltersFromQuery(r.URL.Query())
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	inventory, err := s.operatorReleaseInventory(filters)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	writeJSON(w, http.StatusOK, inventory)
}

func (s *Service) handleSiteOpsAction(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	if !s.requireAdmin(w, r) {
		return
	}
	parts := strings.Split(strings.TrimPrefix(r.URL.Path, "/ops/actions/packages/"), "/")
	if len(parts) < 3 || !safeID(parts[0]) || !safeID(parts[1]) {
		http.NotFound(w, r)
		return
	}
	pub, name := parts[0], parts[1]
	switch {
	case len(parts) == 3 && parts[2] == "visibility":
		visibility := normalizeVisibility(r.FormValue("visibility"))
		if !validVisibility(visibility) {
			http.Error(w, "invalid package visibility", http.StatusBadRequest)
			return
		}
		if _, err := s.setPackageVisibilityValue(pub, name, visibility, s.auditActor(r, pub), "ops.package.visibility"); err != nil {
			http.Error(w, err.Error(), statusForStoreError(err))
			return
		}
	case len(parts) == 5 && parts[2] == "versions" && safeVersion(parts[3]):
		version, action := parts[3], parts[4]
		status := ""
		switch action {
		case "publish":
			status = "published"
		case "yank":
			status = "yanked"
		default:
			http.NotFound(w, r)
			return
		}
		if _, err := s.setReleaseStatusValue(pub, name, version, status, s.auditActor(r, pub), "ops.release."+status); err != nil {
			http.Error(w, err.Error(), statusForStoreError(err))
			return
		}
	default:
		http.NotFound(w, r)
		return
	}
	http.Redirect(w, r, "/ops/releases", http.StatusSeeOther)
}

func (s *Service) operatorReleaseInventory(filters OperatorReleaseFilters) (OperatorReleaseInventory, error) {
	items, err := s.operatorReleaseItems()
	if err != nil {
		return OperatorReleaseInventory{}, err
	}
	total := len(items)
	items = filterOperatorReleaseItems(items, filters)
	return OperatorReleaseInventory{
		Schema:               "oren.obc.store.ops.releases.v0",
		Service:              "obc-store",
		Filters:              filters,
		TotalReleaseCount:    total,
		FilteredReleaseCount: len(items),
		Generated:            s.now().UTC().Format("2006-01-02T15:04:05Z07:00"),
		Releases:             items,
	}, nil
}

func operatorReleaseFiltersFromQuery(q url.Values) (OperatorReleaseFilters, error) {
	filters := OperatorReleaseFilters{
		Status:     normalizeOpsFilter(q.Get("status"), "all"),
		Visibility: normalizeOpsFilter(q.Get("visibility"), "all"),
		Readiness:  normalizeOpsFilter(q.Get("readiness"), "all"),
	}
	if !oneOf(filters.Status, "all", "published", "yanked", "draft") {
		return OperatorReleaseFilters{}, errors.New("invalid status filter")
	}
	if !oneOf(filters.Visibility, "all", "public", "private") {
		return OperatorReleaseFilters{}, errors.New("invalid visibility filter")
	}
	if !oneOf(filters.Readiness, "all", "ready", "incomplete") {
		return OperatorReleaseFilters{}, errors.New("invalid readiness filter")
	}
	return filters, nil
}

func normalizeOpsFilter(v, fallback string) string {
	v = strings.ToLower(strings.TrimSpace(v))
	if v == "" {
		return fallback
	}
	return v
}

func oneOf(v string, allowed ...string) bool {
	for _, a := range allowed {
		if v == a {
			return true
		}
	}
	return false
}

func filterOperatorReleaseItems(items []OperatorReleaseItem, filters OperatorReleaseFilters) []OperatorReleaseItem {
	if filters.Status == "all" && filters.Visibility == "all" && filters.Readiness == "all" {
		return items
	}
	out := make([]OperatorReleaseItem, 0)
	for _, item := range items {
		if filters.Status != "all" && item.Status != filters.Status {
			continue
		}
		if filters.Visibility != "all" && item.Visibility != filters.Visibility {
			continue
		}
		if filters.Readiness == "ready" && len(item.MissingReadiness) != 0 {
			continue
		}
		if filters.Readiness == "incomplete" && len(item.MissingReadiness) == 0 {
			continue
		}
		out = append(out, item)
	}
	return out
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
		OpsPublishURL:    "/ops/actions/packages/" + rel.Publisher + "/" + rel.Name + "/versions/" + rel.Version + "/publish",
		OpsYankURL:       "/ops/actions/packages/" + rel.Publisher + "/" + rel.Name + "/versions/" + rel.Version + "/yank",
		OpsVisibilityURL: "/ops/actions/packages/" + rel.Publisher + "/" + rel.Name + "/visibility",
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

func setReleaseMetaStatus(rel ReleaseMeta, status string, now time.Time) ReleaseMeta {
	rel.Status = status
	rel.UpdatedAt = now.UTC()
	return rel
}

func statusForStoreError(err error) int {
	if errors.Is(err, errPackageNotFound) || errors.Is(err, errReleaseNotFound) {
		return http.StatusNotFound
	}
	return http.StatusInternalServerError
}
