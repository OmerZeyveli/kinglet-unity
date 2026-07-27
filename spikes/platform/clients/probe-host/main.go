// Package main implements the Kinglet native client capability probe.
//
// It is a harmless, standard-library-only fixture that every client overlay
// installs and exercises to prove the client can (a) run a native executable,
// (b) apply a hook decision, and (c) drive a local stdio MCP server. It reads
// two fixed files inside a Unity-shaped project and never touches the network.
//
// Subcommands:
//
//	kinglet-client-probe exec --project <path> --output <path>
//	kinglet-client-probe hook --event <path>|-
//	kinglet-client-probe mcp
package main

import (
	"bufio"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

// ---------------------------------------------------------------------------
// Frozen constants
// ---------------------------------------------------------------------------

const (
	receiptSchema = "kinglet.client-probe.receipt/v1"

	// fixedMarker is the exact content expected in the project-marker file.
	fixedMarker = "KINGLET_CLIENT_PROBE_PROJECT"

	// protectedTarget is the ONLY hook target that is denied.
	protectedTarget = "Assets/Protected.txt"

	// Fixed relative paths inside a Unity-shaped project.
	relProjectVersion = "ProjectSettings/ProjectVersion.txt"
	relMarker         = ".kinglet-probe/project-marker.txt"

	editorVersionKey = "m_EditorVersion:"

	toolName = "kinglet_probe_read_marker"
)

// receipt is the frozen output shape shared by `exec` and the MCP tool.
// Field order is load-bearing: exec writes these exact bytes.
type receipt struct {
	Schema       string `json:"schema"`
	Marker       string `json:"marker"`
	UnityVersion string `json:"unity_version"`
}

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

func main() {
	if err := run(os.Args[1:], os.Stdin, os.Stdout); err != nil {
		fmt.Fprintln(os.Stderr, "kinglet-client-probe:", err)
		os.Exit(1)
	}
}

func run(args []string, stdin io.Reader, stdout io.Writer) error {
	if len(args) == 0 {
		return errors.New("usage: kinglet-client-probe <exec|hook|mcp> [flags]")
	}
	sub := args[0]
	rest := args[1:]

	switch sub {
	case "exec":
		project, output, err := parseExecFlags(rest)
		if err != nil {
			return err
		}
		return runExec(project, output)
	case "hook":
		eventPath, err := parseHookFlags(rest)
		if err != nil {
			return err
		}
		return runHook(eventPath, stdin, stdout)
	case "mcp":
		return serveMCP(stdin, stdout)
	default:
		return fmt.Errorf("unknown subcommand %q", sub)
	}
}

// ---------------------------------------------------------------------------
// Flag parsing (std-lib only, no flag package to keep error messages precise)
// ---------------------------------------------------------------------------

func parseExecFlags(args []string) (project, output string, err error) {
	for i := 0; i < len(args); i++ {
		switch args[i] {
		case "--project":
			if i+1 >= len(args) {
				return "", "", errors.New("--project requires a value")
			}
			project = args[i+1]
			i++
		case "--output":
			if i+1 >= len(args) {
				return "", "", errors.New("--output requires a value")
			}
			output = args[i+1]
			i++
		default:
			return "", "", fmt.Errorf("exec: unexpected argument %q", args[i])
		}
	}
	if project == "" {
		return "", "", errors.New("exec: --project is required")
	}
	if output == "" {
		return "", "", errors.New("exec: --output is required")
	}
	return project, output, nil
}

func parseHookFlags(args []string) (eventPath string, err error) {
	for i := 0; i < len(args); i++ {
		switch args[i] {
		case "--event":
			if i+1 >= len(args) {
				return "", errors.New("--event requires a value")
			}
			eventPath = args[i+1]
			i++
		default:
			return "", fmt.Errorf("hook: unexpected argument %q", args[i])
		}
	}
	if eventPath == "" {
		return "", errors.New("hook: --event is required (path or - for stdin)")
	}
	return eventPath, nil
}

// ---------------------------------------------------------------------------
// exec
// ---------------------------------------------------------------------------

// readReceipt builds the receipt from a Unity-shaped project root, validating
// that both fixed files exist and the marker matches exactly.
func readReceipt(project string) (receipt, error) {
	version, err := readEditorVersion(filepath.Join(project, relProjectVersion))
	if err != nil {
		return receipt{}, err
	}

	markerRaw, err := os.ReadFile(filepath.Join(project, relMarker))
	if err != nil {
		return receipt{}, fmt.Errorf("read marker: %w", err)
	}
	marker := strings.TrimSpace(string(markerRaw))
	if marker != fixedMarker {
		return receipt{}, fmt.Errorf("marker mismatch: got %q, want %q", marker, fixedMarker)
	}

	return receipt{
		Schema:       receiptSchema,
		Marker:       fixedMarker,
		UnityVersion: version,
	}, nil
}

// readEditorVersion reads the m_EditorVersion line. Unity writes two version
// lines; only the exact "m_EditorVersion:" key is honored (not the
// "m_EditorVersionWithRevision:" line).
func readEditorVersion(path string) (string, error) {
	f, err := os.Open(path)
	if err != nil {
		return "", fmt.Errorf("read project version: %w", err)
	}
	defer f.Close()

	sc := bufio.NewScanner(f)
	for sc.Scan() {
		line := strings.TrimSpace(sc.Text())
		if strings.HasPrefix(line, editorVersionKey) {
			return strings.TrimSpace(line[len(editorVersionKey):]), nil
		}
	}
	if err := sc.Err(); err != nil {
		return "", fmt.Errorf("scan project version: %w", err)
	}
	return "", fmt.Errorf("no %s line in %s", editorVersionKey, path)
}

// runExec reads the project and atomically writes the receipt to output.
func runExec(project, output string) error {
	r, err := readReceipt(project)
	if err != nil {
		return err
	}
	data, err := json.Marshal(r)
	if err != nil {
		return fmt.Errorf("marshal receipt: %w", err)
	}
	return atomicWrite(output, data)
}

// atomicWrite creates a unique tmp sibling of target with O_CREATE|O_EXCL,
// writes+fsyncs it, then renames it over target. The tmp file lives in the
// same directory as target (below --output), never elsewhere.
func atomicWrite(target string, data []byte) error {
	parent := filepath.Dir(target)
	if err := os.MkdirAll(parent, 0o755); err != nil {
		return fmt.Errorf("atomicWrite: mkdir: %w", err)
	}

	base := filepath.Base(target)
	tmpPath := filepath.Join(parent, base+".tmp")

	f, err := os.OpenFile(tmpPath, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0o600)
	if err != nil {
		// A stale/concurrent tmp exists — pick a unique sibling name.
		tmpPath = filepath.Join(parent, base+"."+strconv.FormatInt(time.Now().UnixNano(), 16)+".tmp")
		f, err = os.OpenFile(tmpPath, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0o600)
		if err != nil {
			return fmt.Errorf("atomicWrite: create tmp: %w", err)
		}
	}

	cleanup := true
	defer func() {
		if cleanup {
			os.Remove(tmpPath)
		}
	}()

	if _, err := f.Write(data); err != nil {
		f.Close()
		return fmt.Errorf("atomicWrite: write: %w", err)
	}
	if err := f.Sync(); err != nil {
		f.Close()
		return fmt.Errorf("atomicWrite: sync: %w", err)
	}
	if err := f.Close(); err != nil {
		return fmt.Errorf("atomicWrite: close: %w", err)
	}

	if err := os.Rename(tmpPath, target); err != nil {
		return fmt.Errorf("atomicWrite: rename: %w", err)
	}
	cleanup = false

	// Best-effort directory fsync so the rename is durable.
	if dfd, err := os.Open(parent); err == nil {
		dfd.Sync() //nolint:errcheck
		dfd.Close()
	}
	return nil
}

// ---------------------------------------------------------------------------
// hook
// ---------------------------------------------------------------------------

// hookEvent is one incoming event. Only the target path matters here.
type hookEvent struct {
	Path string `json:"path"`
}

// hookDecision is the structured allow/deny response.
type hookDecision struct {
	Decision string `json:"decision"` // "allow" | "deny"
	Target   string `json:"target"`
	Reason   string `json:"reason"`
}

// decideHook denies ONLY when the event targets Assets/Protected.txt.
func decideHook(ev hookEvent) hookDecision {
	target := normalizeTarget(ev.Path)
	if target == protectedTarget {
		return hookDecision{
			Decision: "deny",
			Target:   target,
			Reason:   "target is the protected probe file",
		}
	}
	return hookDecision{
		Decision: "allow",
		Target:   target,
		Reason:   "target is not protected",
	}
}

// normalizeTarget collapses separators to forward slashes so path comparison
// is stable across OSes, without resolving the filesystem.
func normalizeTarget(p string) string {
	return filepath.ToSlash(filepath.Clean(p))
}

// runHook reads ONE event object from the file at eventPath (or stdin when
// eventPath == "-") and writes the decision as a single JSON line.
func runHook(eventPath string, stdin io.Reader, out io.Writer) error {
	var src io.Reader
	if eventPath == "-" {
		if stdin == nil {
			return errors.New("hook: stdin unavailable")
		}
		src = stdin
	} else {
		f, err := os.Open(eventPath)
		if err != nil {
			return fmt.Errorf("hook: open event: %w", err)
		}
		defer f.Close()
		src = f
	}

	// Decode exactly one event object.
	dec := json.NewDecoder(src)
	var ev hookEvent
	if err := dec.Decode(&ev); err != nil {
		return fmt.Errorf("hook: decode event: %w", err)
	}

	decision := decideHook(ev)
	data, err := json.Marshal(decision)
	if err != nil {
		return fmt.Errorf("hook: marshal decision: %w", err)
	}
	if _, err := out.Write(append(data, '\n')); err != nil {
		return fmt.Errorf("hook: write decision: %w", err)
	}
	return nil
}

// ---------------------------------------------------------------------------
// mcp — local stdio JSON-RPC 2.0 server
// ---------------------------------------------------------------------------

type jsonRPCRequest struct {
	JSONRPC string          `json:"jsonrpc"`
	ID      json.RawMessage `json:"id,omitempty"`
	Method  string          `json:"method"`
	Params  json.RawMessage `json:"params,omitempty"`
}

type jsonRPCError struct {
	Code    int    `json:"code"`
	Message string `json:"message"`
}

type jsonRPCResponse struct {
	JSONRPC string          `json:"jsonrpc"`
	ID      json.RawMessage `json:"id,omitempty"`
	Result  json.RawMessage `json:"result,omitempty"`
	Error   *jsonRPCError   `json:"error,omitempty"`
}

// serveMCP reads newline-delimited JSON-RPC requests from in and writes one
// response line per request that carries an id. Notifications (no id) get no
// response. It answers only the four supported methods; everything else is a
// -32601 error.
func serveMCP(in io.Reader, out io.Writer) error {
	dec := json.NewDecoder(bufio.NewReader(in))
	for {
		var req jsonRPCRequest
		if err := dec.Decode(&req); err != nil {
			if errors.Is(err, io.EOF) {
				return nil
			}
			return fmt.Errorf("mcp: decode: %w", err)
		}

		isNotification := len(req.ID) == 0

		switch req.Method {
		case "notifications/initialized":
			// Notification — no response.
			continue
		case "initialize":
			if err := writeResult(out, req.ID, initializeResult()); err != nil {
				return err
			}
		case "tools/list":
			if err := writeResult(out, req.ID, toolsListResult()); err != nil {
				return err
			}
		case "tools/call":
			result, rpcErr := handleToolsCall(req.Params)
			if rpcErr != nil {
				if err := writeError(out, req.ID, rpcErr.Code, rpcErr.Message); err != nil {
					return err
				}
				continue
			}
			if err := writeResult(out, req.ID, result); err != nil {
				return err
			}
		default:
			if isNotification {
				// Unknown notification: nothing to respond to.
				continue
			}
			if err := writeError(out, req.ID, -32601, "method not found: "+req.Method); err != nil {
				return err
			}
		}
	}
}

func initializeResult() any {
	return map[string]any{
		"protocolVersion": "2025-06-18",
		"capabilities": map[string]any{
			"tools": map[string]any{},
		},
		"serverInfo": map[string]any{
			"name":    "kinglet-client-probe",
			"version": "1",
		},
	}
}

func toolsListResult() any {
	return map[string]any{
		"tools": []any{
			map[string]any{
				"name":        toolName,
				"description": "Read the fixed Kinglet client-probe marker from a Unity project root. Read-only.",
				"inputSchema": map[string]any{
					"type": "object",
					"properties": map[string]any{
						"project_root": map[string]any{
							"type":        "string",
							"description": "Absolute path to the Unity-shaped project root.",
						},
					},
					"required": []any{"project_root"},
				},
			},
		},
	}
}

// handleToolsCall dispatches the single supported tool. It NEVER writes to the
// filesystem — it only reads the two fixed files via readReceipt.
func handleToolsCall(params json.RawMessage) (any, *jsonRPCError) {
	var call struct {
		Name      string `json:"name"`
		Arguments struct {
			ProjectRoot string `json:"project_root"`
		} `json:"arguments"`
	}
	if err := json.Unmarshal(params, &call); err != nil {
		return nil, &jsonRPCError{Code: -32602, Message: "invalid params: " + err.Error()}
	}
	if call.Name != toolName {
		return nil, &jsonRPCError{Code: -32602, Message: "unknown tool: " + call.Name}
	}
	if call.Arguments.ProjectRoot == "" {
		return nil, &jsonRPCError{Code: -32602, Message: "project_root is required"}
	}

	r, err := readReceipt(call.Arguments.ProjectRoot)
	if err != nil {
		// Tool-level error surfaced in the result, per MCP convention.
		return map[string]any{
			"isError": true,
			"content": []any{
				map[string]any{"type": "text", "text": err.Error()},
			},
		}, nil
	}

	text, _ := json.Marshal(r)
	return map[string]any{
		"content": []any{
			map[string]any{"type": "text", "text": string(text)},
		},
		"structuredContent": r,
	}, nil
}

func writeResult(out io.Writer, id json.RawMessage, result any) error {
	raw, err := json.Marshal(result)
	if err != nil {
		return fmt.Errorf("mcp: marshal result: %w", err)
	}
	return writeResponse(out, jsonRPCResponse{
		JSONRPC: "2.0",
		ID:      id,
		Result:  raw,
	})
}

func writeError(out io.Writer, id json.RawMessage, code int, message string) error {
	return writeResponse(out, jsonRPCResponse{
		JSONRPC: "2.0",
		ID:      id,
		Error:   &jsonRPCError{Code: code, Message: message},
	})
}

func writeResponse(out io.Writer, resp jsonRPCResponse) error {
	data, err := json.Marshal(resp)
	if err != nil {
		return fmt.Errorf("mcp: marshal response: %w", err)
	}
	if _, err := out.Write(append(data, '\n')); err != nil {
		return fmt.Errorf("mcp: write response: %w", err)
	}
	return nil
}
