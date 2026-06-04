package obcstore

import (
	"net/http"
	"strings"
)

type PackageUpdateStatus struct {
	Publisher       string       `json:"publisher"`
	Name            string       `json:"name"`
	CurrentVersion  string       `json:"current_version,omitempty"`
	LatestVersion   string       `json:"latest_version,omitempty"`
	UpdateAvailable bool         `json:"update_available"`
	LatestRelease   *ReleaseMeta `json:"latest_release,omitempty"`
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
