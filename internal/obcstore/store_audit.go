package obcstore

import (
	"bufio"
	"encoding/json"
	"errors"
	"net/http"
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
	Schema    string       `json:"schema"`
	Service   string       `json:"service"`
	Generated string       `json:"generated_at"`
	Events    []AuditEvent `json:"events"`
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
	log, err := s.operatorAuditLog(limitFromQuery(r, 100))
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
	log, err := s.operatorAuditLog(limitFromQuery(r, 100))
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	writeJSON(w, http.StatusOK, log)
}

func (s *Service) operatorAuditLog(limit int) (OperatorAuditLog, error) {
	events, err := s.auditEvents(limit)
	if err != nil {
		return OperatorAuditLog{}, err
	}
	return OperatorAuditLog{
		Schema:    auditSchema,
		Service:   "obc-store",
		Generated: s.now().UTC().Format(time.RFC3339),
		Events:    nonNilAuditEvents(events),
	}, nil
}

func (s *Service) auditEvents(limit int) ([]AuditEvent, error) {
	if limit <= 0 || limit > 500 {
		limit = 100
	}
	file, err := os.Open(s.auditLogPath())
	if errors.Is(err, os.ErrNotExist) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	defer file.Close()

	var ring []AuditEvent
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
		ring = append(ring, ev)
		if len(ring) > limit {
			copy(ring, ring[1:])
			ring = ring[:limit]
		}
	}
	if err := scanner.Err(); err != nil {
		return nil, err
	}
	for i, j := 0, len(ring)-1; i < j; i, j = i+1, j-1 {
		ring[i], ring[j] = ring[j], ring[i]
	}
	return ring, nil
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
	raw := strings.TrimSpace(r.URL.Query().Get("limit"))
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
