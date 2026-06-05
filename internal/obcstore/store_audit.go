package obcstore

import (
	"bufio"
	"encoding/json"
	"errors"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

const auditSchema = "oren.obc.store.audit.v0"

type AuditActor struct {
	Kind string `json:"kind"`
	ID   string `json:"id,omitempty"`
}

type AuditEvent struct {
	Schema    string            `json:"schema"`
	Timestamp string            `json:"timestamp"`
	Actor     AuditActor        `json:"actor"`
	Action    string            `json:"action"`
	Target    string            `json:"target"`
	Details   map[string]string `json:"details,omitempty"`
}

type OperatorAuditLog struct {
	Schema             string               `json:"schema"`
	Service            string               `json:"service"`
	Filters            OperatorAuditFilters `json:"filters"`
	TotalEventCount    int                  `json:"total_event_count"`
	FilteredEventCount int                  `json:"filtered_event_count"`
	Generated          string               `json:"generated_at"`
	Events             []AuditEvent         `json:"events"`
}

type OperatorAuditFilters struct {
	Limit          int    `json:"limit"`
	Action         string `json:"action,omitempty"`
	ActorKind      string `json:"actor_kind,omitempty"`
	ActorID        string `json:"actor_id,omitempty"`
	TargetContains string `json:"target_contains,omitempty"`
}

func (s *Service) handleSiteOpsAudit(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path != "/ops/audit" {
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
	filters, err := operatorAuditFiltersFromQuery(r.URL.Query(), 100)
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	log, err := s.operatorAuditLog(filters)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	renderHTML(w, siteOpsAuditTemplate, log)
}

func (s *Service) handleOpsAudit(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	if !s.requireAdmin(w, r) {
		return
	}
	filters, err := operatorAuditFiltersFromQuery(r.URL.Query(), 100)
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	log, err := s.operatorAuditLog(filters)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	writeJSON(w, http.StatusOK, log)
}

func (s *Service) operatorAuditLog(filters OperatorAuditFilters) (OperatorAuditLog, error) {
	events, total, matched, err := s.auditEvents(filters)
	if err != nil {
		return OperatorAuditLog{}, err
	}
	return OperatorAuditLog{
		Schema:             auditSchema,
		Service:            "obc-store",
		Filters:            filters,
		TotalEventCount:    total,
		FilteredEventCount: matched,
		Generated:          s.now().UTC().Format(time.RFC3339),
		Events:             nonNilAuditEvents(events),
	}, nil
}

func (s *Service) auditEvents(filters OperatorAuditFilters) ([]AuditEvent, int, int, error) {
	limit := filters.Limit
	file, err := os.Open(s.auditLogPath())
	if errors.Is(err, os.ErrNotExist) {
		return nil, 0, 0, nil
	}
	if err != nil {
		return nil, 0, 0, err
	}
	defer file.Close()

	var ring []AuditEvent
	total := 0
	matched := 0
	scanner := bufio.NewScanner(file)
	scanner.Buffer(make([]byte, 0, 4096), 1024*1024)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" {
			continue
		}
		var ev AuditEvent
		if err := json.Unmarshal([]byte(line), &ev); err != nil {
			continue
		}
		total++
		if !auditEventMatches(ev, filters) {
			continue
		}
		matched++
		ring = append(ring, ev)
		if len(ring) > limit {
			copy(ring, ring[1:])
			ring = ring[:limit]
		}
	}
	if err := scanner.Err(); err != nil {
		return nil, 0, 0, err
	}
	for i, j := 0, len(ring)-1; i < j; i, j = i+1, j-1 {
		ring[i], ring[j] = ring[j], ring[i]
	}
	return ring, total, matched, nil
}

func operatorAuditFiltersFromQuery(q url.Values, fallbackLimit int) (OperatorAuditFilters, error) {
	filters := OperatorAuditFilters{
		Limit:          limitFromQueryValues(q, fallbackLimit),
		Action:         strings.TrimSpace(q.Get("action")),
		ActorKind:      strings.ToLower(strings.TrimSpace(q.Get("actor_kind"))),
		ActorID:        strings.TrimSpace(q.Get("actor_id")),
		TargetContains: strings.TrimSpace(q.Get("target")),
	}
	if filters.Action != "" && !safeAuditFilterValue(filters.Action, 128) {
		return OperatorAuditFilters{}, errors.New("invalid action filter")
	}
	if filters.ActorKind != "" && !oneOf(filters.ActorKind, "admin", "publisher", "unknown") {
		return OperatorAuditFilters{}, errors.New("invalid actor_kind filter")
	}
	if filters.ActorID != "" && !safeAuditFilterValue(filters.ActorID, 128) {
		return OperatorAuditFilters{}, errors.New("invalid actor_id filter")
	}
	if filters.TargetContains != "" && !safeAuditFilterValue(filters.TargetContains, 256) {
		return OperatorAuditFilters{}, errors.New("invalid target filter")
	}
	return filters, nil
}

func safeAuditFilterValue(v string, maxLen int) bool {
	if len(v) > maxLen {
		return false
	}
	for _, ch := range v {
		if ch < 32 || ch == 127 {
			return false
		}
	}
	return true
}

func auditEventMatches(ev AuditEvent, filters OperatorAuditFilters) bool {
	if filters.Action != "" && ev.Action != filters.Action {
		return false
	}
	if filters.ActorKind != "" && ev.Actor.Kind != filters.ActorKind {
		return false
	}
	if filters.ActorID != "" && ev.Actor.ID != filters.ActorID {
		return false
	}
	if filters.TargetContains != "" && !strings.Contains(ev.Target, filters.TargetContains) {
		return false
	}
	return true
}

func (s *Service) auditEventCount() (int, error) {
	file, err := os.Open(s.auditLogPath())
	if errors.Is(err, os.ErrNotExist) {
		return 0, nil
	}
	if err != nil {
		return 0, err
	}
	defer file.Close()
	count := 0
	scanner := bufio.NewScanner(file)
	scanner.Buffer(make([]byte, 0, 4096), 1024*1024)
	for scanner.Scan() {
		if strings.TrimSpace(scanner.Text()) != "" {
			count++
		}
	}
	return count, scanner.Err()
}

func (s *Service) appendAuditEventLocked(actor AuditActor, action, target string, details map[string]string) error {
	if details != nil {
		for key, value := range details {
			if value == "" {
				delete(details, key)
			}
		}
	}
	ev := AuditEvent{
		Schema:    auditSchema,
		Timestamp: s.now().UTC().Format(time.RFC3339),
		Actor:     actor,
		Action:    action,
		Target:    target,
		Details:   details,
	}
	body, err := json.Marshal(ev)
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(s.auditLogPath()), 0o755); err != nil {
		return err
	}
	body = append(body, '\n')
	return appendFile(s.auditLogPath(), body)
}

func nonNilAuditEvents(events []AuditEvent) []AuditEvent {
	if events == nil {
		return []AuditEvent{}
	}
	return events
}

func (s *Service) auditActor(r *http.Request, publisherID string) AuditActor {
	if s.adminAuthorized(r) {
		id := s.adminUser
		if id == "" {
			id = "admin"
		}
		return AuditActor{Kind: "admin", ID: id}
	}
	if publisherID != "" && s.publisherAuthorized(publisherID, r) {
		return AuditActor{Kind: "publisher", ID: publisherID}
	}
	return AuditActor{Kind: "unknown"}
}

func (s *Service) auditLogPath() string {
	return filepath.Join(s.dataDir, "audit", "audit.log.jsonl")
}

func limitFromQuery(r *http.Request, fallback int) int {
	return limitFromQueryValues(r.URL.Query(), fallback)
}

func limitFromQueryValues(q url.Values, fallback int) int {
	raw := strings.TrimSpace(q.Get("limit"))
	if raw == "" {
		return fallback
	}
	n, err := strconv.Atoi(raw)
	if err != nil || n <= 0 {
		return fallback
	}
	if n > 500 {
		return 500
	}
	return n
}

func appendFile(path string, body []byte) error {
	file, err := os.OpenFile(path, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o644)
	if err != nil {
		return err
	}
	defer file.Close()
	_, err = file.Write(body)
	return err
}

func releaseTarget(pub, name, version string) string {
	return "packages/" + pub + "/" + name + "/versions/" + version
}

func boolString(v bool) string {
	if v {
		return "true"
	}
	return "false"
}
