package obcstore

import (
	"errors"
	"net/http"
	"net/url"
	"sort"
	"strings"
	"time"
)

type PackageUpdateStatus struct {
	Publisher       string       `json:"publisher"`
	Name            string       `json:"name"`
	CurrentVersion  string       `json:"current_version,omitempty"`
	LatestVersion   string       `json:"latest_version,omitempty"`
	UpdateAvailable bool         `json:"update_available"`
	LatestRelease   *ReleaseMeta `json:"latest_release,omitempty"`
}

type OperatorUpdateItem struct {
	Publisher          string   `json:"publisher"`
	Name               string   `json:"name"`
	Title              string   `json:"title,omitempty"`
	Visibility         string   `json:"visibility"`
	LatestVersion      string   `json:"latest_version,omitempty"`
	PublishedVersions  []string `json:"published_versions"`
	SupersededVersions []string `json:"superseded_versions"`
	UpdateURLTemplate  string   `json:"update_url_template"`
	PackageURL         string   `json:"package_url"`
}

type OperatorUpdateInventory struct {
	Schema               string                `json:"schema"`
	Service              string                `json:"service"`
	Filters              OperatorUpdateFilters `json:"filters"`
	TotalPackageCount    int                   `json:"total_package_count"`
	FilteredPackageCount int                   `json:"filtered_package_count"`
	Generated            string                `json:"generated_at"`
	Packages             []OperatorUpdateItem  `json:"packages"`
}

type OperatorUpdateFilters struct {
	Publisher  string `json:"publisher,omitempty"`
	Package    string `json:"package,omitempty"`
	Visibility string `json:"visibility"`
	Superseded string `json:"superseded"`
}

func (s *Service) handleSiteOpsUpdates(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path != "/ops/updates" {
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
	filters, err := operatorUpdateFiltersFromQuery(r.URL.Query())
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	inventory, err := s.operatorUpdateInventory(filters)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	renderHTML(w, siteOpsUpdatesTemplate, inventory)
}

func (s *Service) handleOpsUpdates(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	if !s.requireAdmin(w, r) {
		return
	}
	filters, err := operatorUpdateFiltersFromQuery(r.URL.Query())
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	inventory, err := s.operatorUpdateInventory(filters)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	writeJSON(w, http.StatusOK, inventory)
}

func (s *Service) operatorUpdateInventory(filters OperatorUpdateFilters) (OperatorUpdateInventory, error) {
	items, err := s.operatorUpdateItems()
	if err != nil {
		return OperatorUpdateInventory{}, err
	}
	total := len(items)
	items = filterOperatorUpdateItems(items, filters)
	return OperatorUpdateInventory{
		Schema:               "oren.obc.store.ops.updates.v0",
		Service:              "obc-store",
		Filters:              filters,
		TotalPackageCount:    total,
		FilteredPackageCount: len(items),
		Generated:            s.now().UTC().Format(time.RFC3339),
		Packages:             nonNilOperatorUpdateItems(items),
	}, nil
}

func operatorUpdateFiltersFromQuery(q url.Values) (OperatorUpdateFilters, error) {
	filters := OperatorUpdateFilters{
		Publisher:  strings.TrimSpace(q.Get("publisher")),
		Package:    strings.TrimSpace(q.Get("package")),
		Visibility: normalizeOpsFilter(q.Get("visibility"), "all"),
		Superseded: normalizeOpsFilter(q.Get("superseded"), "all"),
	}
	if filters.Publisher != "" && !safeID(filters.Publisher) {
		return OperatorUpdateFilters{}, errors.New("invalid publisher filter")
	}
	if filters.Package != "" && !safeID(filters.Package) {
		return OperatorUpdateFilters{}, errors.New("invalid package filter")
	}
	if !oneOf(filters.Visibility, "all", "public", "private") {
		return OperatorUpdateFilters{}, errors.New("invalid visibility filter")
	}
	if !oneOf(filters.Superseded, "all", "any", "none") {
		return OperatorUpdateFilters{}, errors.New("invalid superseded filter")
	}
	return filters, nil
}

func filterOperatorUpdateItems(items []OperatorUpdateItem, filters OperatorUpdateFilters) []OperatorUpdateItem {
	if filters.Publisher == "" && filters.Package == "" && filters.Visibility == "all" && filters.Superseded == "all" {
		return items
	}
	out := make([]OperatorUpdateItem, 0)
	for _, item := range items {
		if filters.Publisher != "" && item.Publisher != filters.Publisher {
			continue
		}
		if filters.Package != "" && item.Name != filters.Package {
			continue
		}
		if filters.Visibility != "all" && item.Visibility != filters.Visibility {
			continue
		}
		if filters.Superseded == "any" && len(item.SupersededVersions) == 0 {
			continue
		}
		if filters.Superseded == "none" && len(item.SupersededVersions) != 0 {
			continue
		}
		out = append(out, item)
	}
	return out
}

func (s *Service) operatorUpdateItems() ([]OperatorUpdateItem, error) {
	packages, err := s.allPackageMeta()
	if err != nil {
		return nil, err
	}
	keys := make([]string, 0, len(packages))
	for key := range packages {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	items := make([]OperatorUpdateItem, 0, len(keys))
	for _, key := range keys {
		meta := packages[key]
		releases, err := s.packageReleases(meta.Publisher, meta.Name)
		if err != nil {
			continue
		}
		versions := publishedVersions(releases)
		sort.Slice(versions, func(i, j int) bool { return compareVersions(versions[i], versions[j]) < 0 })
		latest := ""
		if len(versions) > 0 {
			latest = versions[len(versions)-1]
		}
		superseded := []string{}
		if len(versions) > 1 {
			superseded = append(superseded, versions[:len(versions)-1]...)
		}
		items = append(items, OperatorUpdateItem{
			Publisher:          meta.Publisher,
			Name:               meta.Name,
			Title:              meta.Title,
			Visibility:         normalizeVisibility(meta.Visibility),
			LatestVersion:      latest,
			PublishedVersions:  nonNilStrings(versions),
			SupersededVersions: nonNilStrings(superseded),
			UpdateURLTemplate:  "/api/v0/packages/" + meta.Publisher + "/" + meta.Name + "/update?current_version=<installed-version>",
			PackageURL:         "/packages/" + meta.Publisher + "/" + meta.Name,
		})
	}
	return items, nil
}

func (s *Service) getPackageUpdate(w http.ResponseWriter, r *http.Request, pub, name string) {
	meta, err := readJSONFile[PackageMeta](s.packageMetaPath(pub, name))
	if err != nil {
		http.NotFound(w, r)
		return
	}
	if !s.packageVisibleToRequest(meta, r) {
		http.NotFound(w, r)
		return
	}
	current := strings.TrimSpace(r.URL.Query().Get("current_version"))
	if current != "" && !safeVersion(current) {
		http.Error(w, "invalid current_version", http.StatusBadRequest)
		return
	}
	latest, ok, err := s.latestPublishedRelease(pub, name)
	if err != nil {
		http.NotFound(w, r)
		return
	}
	status := PackageUpdateStatus{
		Publisher:      pub,
		Name:           name,
		CurrentVersion: current,
	}
	if ok {
		status.LatestVersion = latest.Version
		status.LatestRelease = &latest
		status.UpdateAvailable = current == "" || compareVersions(latest.Version, current) > 0
	}
	writeJSON(w, http.StatusOK, status)
}

func (s *Service) latestPublishedRelease(pub, name string) (ReleaseMeta, bool, error) {
	releases, err := s.packageReleases(pub, name)
	if err != nil {
		return ReleaseMeta{}, false, err
	}
	var latest ReleaseMeta
	found := false
	for _, rel := range releases {
		if rel.Status != "published" {
			continue
		}
		if !found || compareVersions(rel.Version, latest.Version) > 0 {
			latest = rel
			found = true
		}
	}
	return latest, found, nil
}

func publishedVersions(releases []ReleaseMeta) []string {
	out := []string{}
	for _, rel := range releases {
		if rel.Status == "published" {
			out = append(out, rel.Version)
		}
	}
	return out
}

func nonNilOperatorUpdateItems(items []OperatorUpdateItem) []OperatorUpdateItem {
	if items == nil {
		return []OperatorUpdateItem{}
	}
	return items
}

func nonNilStrings(items []string) []string {
	if items == nil {
		return []string{}
	}
	return items
}

func compareVersions(a, b string) int {
	aCore, aPre := splitVersion(a)
	bCore, bPre := splitVersion(b)
	maxCore := len(aCore)
	if len(bCore) > maxCore {
		maxCore = len(bCore)
	}
	for i := 0; i < maxCore; i++ {
		av := "0"
		bv := "0"
		if i < len(aCore) {
			av = aCore[i]
		}
		if i < len(bCore) {
			bv = bCore[i]
		}
		if c := compareVersionIdentifier(av, bv); c != 0 {
			return c
		}
	}
	if len(aPre) == 0 && len(bPre) == 0 {
		return 0
	}
	if len(aPre) == 0 {
		return 1
	}
	if len(bPre) == 0 {
		return -1
	}
	maxPre := len(aPre)
	if len(bPre) > maxPre {
		maxPre = len(bPre)
	}
	for i := 0; i < maxPre; i++ {
		if i >= len(aPre) {
			return -1
		}
		if i >= len(bPre) {
			return 1
		}
		if c := compareVersionIdentifier(aPre[i], bPre[i]); c != 0 {
			return c
		}
	}
	return 0
}

func splitVersion(v string) ([]string, []string) {
	main := strings.SplitN(v, "+", 2)[0]
	core := main
	var pre []string
	if parts := strings.SplitN(main, "-", 2); len(parts) == 2 {
		core = parts[0]
		pre = strings.Split(parts[1], ".")
	}
	return strings.Split(core, "."), pre
}

func compareVersionIdentifier(a, b string) int {
	aNum := allDigits(a)
	bNum := allDigits(b)
	if aNum && bNum {
		return compareNumericStrings(a, b)
	}
	if aNum {
		return -1
	}
	if bNum {
		return 1
	}
	return strings.Compare(a, b)
}

func compareNumericStrings(a, b string) int {
	a = strings.TrimLeft(a, "0")
	b = strings.TrimLeft(b, "0")
	if a == "" {
		a = "0"
	}
	if b == "" {
		b = "0"
	}
	if len(a) < len(b) {
		return -1
	}
	if len(a) > len(b) {
		return 1
	}
	return strings.Compare(a, b)
}

func allDigits(s string) bool {
	if s == "" {
		return false
	}
	for _, r := range s {
		if r < '0' || r > '9' {
			return false
		}
	}
	return true
}
