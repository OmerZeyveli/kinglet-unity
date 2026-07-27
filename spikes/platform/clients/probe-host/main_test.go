package main

import (
	"bufio"
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
)

// mkUnityProject builds a Unity-shaped temp directory:
//
//	ProjectSettings/ProjectVersion.txt : m_EditorVersion: 6000.3.11f1
//	.kinglet-probe/project-marker.txt  : KINGLET_CLIENT_PROBE_PROJECT
//	Assets/Protected.txt               : PROTECTED
func mkUnityProject(t *testing.T) string {
	t.Helper()
	root := t.TempDir()

	write := func(rel, body string) {
		p := filepath.Join(root, rel)
		if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
			t.Fatalf("mkdir %s: %v", rel, err)
		}
		if err := os.WriteFile(p, []byte(body), 0o644); err != nil {
			t.Fatalf("write %s: %v", rel, err)
		}
	}

	// Unity writes two lines; the version regex must match the first.
	write("ProjectSettings/ProjectVersion.txt", "m_EditorVersion: 6000.3.11f1\nm_EditorVersionWithRevision: 6000.3.11f1 (abcdef012345)\n")
	write(".kinglet-probe/project-marker.txt", "KINGLET_CLIENT_PROBE_PROJECT\n")
	write("Assets/Protected.txt", "PROTECTED\n")
	return root
}

const (
	wantSchema  = "kinglet.client-probe.receipt/v1"
	wantMarker  = "KINGLET_CLIENT_PROBE_PROJECT"
	wantVersion = "6000.3.11f1"
)

func assertReceipt(t *testing.T, r receipt) {
	t.Helper()
	if r.Schema != wantSchema {
		t.Errorf("schema = %q, want %q", r.Schema, wantSchema)
	}
	if r.Marker != wantMarker {
		t.Errorf("marker = %q, want %q", r.Marker, wantMarker)
	}
	if r.UnityVersion != wantVersion {
		t.Errorf("unity_version = %q, want %q", r.UnityVersion, wantVersion)
	}
}

// --- exec ------------------------------------------------------------------

func TestExecWritesExactReceiptAtomically(t *testing.T) {
	root := mkUnityProject(t)
	outDir := t.TempDir()
	out := filepath.Join(outDir, "receipt.json")

	if err := runExec(root, out); err != nil {
		t.Fatalf("runExec: %v", err)
	}

	raw, err := os.ReadFile(out)
	if err != nil {
		t.Fatalf("read output: %v", err)
	}

	var r receipt
	if err := json.Unmarshal(raw, &r); err != nil {
		t.Fatalf("output is not valid JSON: %v", err)
	}
	assertReceipt(t, r)

	// Exact byte payload (field order and content are frozen).
	want := `{"schema":"kinglet.client-probe.receipt/v1","marker":"KINGLET_CLIENT_PROBE_PROJECT","unity_version":"6000.3.11f1"}`
	if string(raw) != want {
		t.Errorf("exact bytes mismatch:\n got %s\nwant %s", raw, want)
	}

	// No partial / tmp leftovers beside the output.
	entries, err := os.ReadDir(outDir)
	if err != nil {
		t.Fatalf("read outdir: %v", err)
	}
	if len(entries) != 1 || entries[0].Name() != "receipt.json" {
		names := []string{}
		for _, e := range entries {
			names = append(names, e.Name())
		}
		t.Errorf("expected only receipt.json in output dir, got %v", names)
	}
}

// TestExecOnlyWritesBelowOutput proves the atomic tmp file never lands outside
// the output's own directory: only the final file and (transiently) its
// sibling tmp are created, both below --output's parent.
func TestExecOnlyWritesBelowOutput(t *testing.T) {
	root := mkUnityProject(t)
	outDir := t.TempDir()
	out := filepath.Join(outDir, "nested", "receipt.json")

	if err := runExec(root, out); err != nil {
		t.Fatalf("runExec: %v", err)
	}

	// Walk the whole outDir tree; every created file must be at or below the
	// output's parent directory (outDir/nested), never a sibling of outDir.
	wantParent := filepath.Clean(filepath.Dir(out))
	var found []string
	err := filepath.Walk(outDir, func(p string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		if info.IsDir() {
			return nil
		}
		found = append(found, p)
		if filepath.Clean(filepath.Dir(p)) != wantParent {
			t.Errorf("exec wrote %s outside output parent %s", p, wantParent)
		}
		return nil
	})
	if err != nil {
		t.Fatalf("walk: %v", err)
	}
	if len(found) != 1 || filepath.Clean(found[0]) != filepath.Clean(out) {
		t.Errorf("expected only the output file, got %v", found)
	}
}

// --- hook ------------------------------------------------------------------

func TestHookDeniesOnlyProtected(t *testing.T) {
	cases := []struct {
		target   string
		wantDeny bool
	}{
		{"Assets/Protected.txt", true},
		{"Assets/Player.cs", false},
		{"ProjectSettings/ProjectVersion.txt", false},
		{".kinglet-probe/project-marker.txt", false},
		{"Assets/sub/Protected.txt", false}, // exact target only
	}

	for _, c := range cases {
		ev := hookEvent{Path: c.target}
		dec := decideHook(ev)
		gotDeny := dec.Decision == "deny"
		if gotDeny != c.wantDeny {
			t.Errorf("target %q: decision = %q (deny=%v), want deny=%v",
				c.target, dec.Decision, gotDeny, c.wantDeny)
		}
		if dec.Decision != "deny" && dec.Decision != "allow" {
			t.Errorf("target %q: decision must be allow|deny, got %q", c.target, dec.Decision)
		}
	}
}

func TestRunHookReadsEventFromFile(t *testing.T) {
	dir := t.TempDir()
	evPath := filepath.Join(dir, "event.json")
	if err := os.WriteFile(evPath, []byte(`{"path":"Assets/Protected.txt"}`), 0o644); err != nil {
		t.Fatal(err)
	}
	var buf bytes.Buffer
	if err := runHook(evPath, nil, &buf); err != nil {
		t.Fatalf("runHook: %v", err)
	}
	var dec hookDecision
	if err := json.Unmarshal(buf.Bytes(), &dec); err != nil {
		t.Fatalf("decision not JSON: %v (%s)", err, buf.String())
	}
	if dec.Decision != "deny" {
		t.Errorf("decision = %q, want deny", dec.Decision)
	}
}

func TestRunHookReadsEventFromStdin(t *testing.T) {
	in := strings.NewReader(`{"path":"Assets/Player.cs"}`)
	var buf bytes.Buffer
	if err := runHook("-", in, &buf); err != nil {
		t.Fatalf("runHook stdin: %v", err)
	}
	var dec hookDecision
	if err := json.Unmarshal(buf.Bytes(), &dec); err != nil {
		t.Fatalf("decision not JSON: %v", err)
	}
	if dec.Decision != "allow" {
		t.Errorf("decision = %q, want allow", dec.Decision)
	}
}

// --- mcp -------------------------------------------------------------------

// rpc drives the MCP server: writes a single request line, reads a single
// response, and returns the decoded envelope.
func rpc(t *testing.T, req string) jsonRPCResponse {
	t.Helper()
	in := strings.NewReader(req + "\n")
	var out bytes.Buffer
	if err := serveMCP(in, &out); err != nil {
		t.Fatalf("serveMCP: %v", err)
	}
	sc := bufio.NewScanner(&out)
	sc.Buffer(make([]byte, 0, 64*1024), 1<<20)
	if !sc.Scan() {
		t.Fatalf("no response line for req %s", req)
	}
	var resp jsonRPCResponse
	if err := json.Unmarshal(sc.Bytes(), &resp); err != nil {
		t.Fatalf("response not JSON: %v (%s)", err, sc.Text())
	}
	if resp.JSONRPC != "2.0" {
		t.Errorf("jsonrpc = %q, want 2.0", resp.JSONRPC)
	}
	return resp
}

func TestMCPInitialize(t *testing.T) {
	resp := rpc(t, `{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}`)
	if resp.Error != nil {
		t.Fatalf("initialize returned error: %+v", resp.Error)
	}
	if resp.Result == nil {
		t.Fatal("initialize returned no result")
	}
}

func TestMCPToolsList(t *testing.T) {
	resp := rpc(t, `{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}`)
	if resp.Error != nil {
		t.Fatalf("tools/list error: %+v", resp.Error)
	}
	var res struct {
		Tools []struct {
			Name string `json:"name"`
		} `json:"tools"`
	}
	if err := json.Unmarshal(resp.Result, &res); err != nil {
		t.Fatalf("tools/list result: %v", err)
	}
	if len(res.Tools) != 1 || res.Tools[0].Name != "kinglet_probe_read_marker" {
		t.Errorf("tools = %+v, want exactly [kinglet_probe_read_marker]", res.Tools)
	}
}

func TestMCPToolsCallReturnsReceipt(t *testing.T) {
	root := mkUnityProject(t)
	// project_root arrives as a JSON string; escape backslashes for Windows paths.
	rootJSON, _ := json.Marshal(root)
	req := `{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"kinglet_probe_read_marker","arguments":{"project_root":` + string(rootJSON) + `}}}`
	resp := rpc(t, req)
	if resp.Error != nil {
		t.Fatalf("tools/call error: %+v", resp.Error)
	}

	// MCP tools/call wraps output in content[]; the receipt is JSON text there,
	// and structuredContent carries it as an object.
	var res struct {
		StructuredContent receipt `json:"structuredContent"`
		Content           []struct {
			Type string `json:"type"`
			Text string `json:"text"`
		} `json:"content"`
	}
	if err := json.Unmarshal(resp.Result, &res); err != nil {
		t.Fatalf("tools/call result: %v", err)
	}
	assertReceipt(t, res.StructuredContent)

	if len(res.Content) == 0 {
		t.Fatal("tools/call returned no content")
	}
	var textReceipt receipt
	if err := json.Unmarshal([]byte(res.Content[0].Text), &textReceipt); err != nil {
		t.Fatalf("content text not a receipt: %v", err)
	}
	assertReceipt(t, textReceipt)
}

func TestMCPToolsCallNeverWrites(t *testing.T) {
	root := mkUnityProject(t)
	before := snapshotTree(t, root)

	rootJSON, _ := json.Marshal(root)
	req := `{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"kinglet_probe_read_marker","arguments":{"project_root":` + string(rootJSON) + `}}}`
	_ = rpc(t, req)

	after := snapshotTree(t, root)
	if before != after {
		t.Errorf("tools/call mutated the project tree:\nbefore:\n%s\nafter:\n%s", before, after)
	}
}

func TestMCPUnknownMethod(t *testing.T) {
	resp := rpc(t, `{"jsonrpc":"2.0","id":5,"method":"resources/list","params":{}}`)
	if resp.Error == nil {
		t.Fatal("unknown method should return an error")
	}
	if resp.Error.Code != -32601 {
		t.Errorf("error code = %d, want -32601", resp.Error.Code)
	}
}

func TestMCPNotificationsInitializedNoResponse(t *testing.T) {
	// A notification (no id) must not produce a response line.
	in := strings.NewReader(`{"jsonrpc":"2.0","method":"notifications/initialized"}` + "\n")
	var out bytes.Buffer
	if err := serveMCP(in, &out); err != nil {
		t.Fatalf("serveMCP: %v", err)
	}
	if strings.TrimSpace(out.String()) != "" {
		t.Errorf("notification produced a response: %q", out.String())
	}
}

// snapshotTree returns a stable string of relative path + size for every file
// under root, used to prove read-only behavior.
func snapshotTree(t *testing.T, root string) string {
	t.Helper()
	var sb strings.Builder
	err := filepath.Walk(root, func(p string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		if info.IsDir() {
			return nil
		}
		rel, _ := filepath.Rel(root, p)
		sb.WriteString(rel)
		sb.WriteByte(':')
		sb.WriteString(strconv.FormatInt(info.Size(), 10))
		sb.WriteByte('\n')
		return nil
	})
	if err != nil {
		t.Fatalf("walk: %v", err)
	}
	return sb.String()
}
