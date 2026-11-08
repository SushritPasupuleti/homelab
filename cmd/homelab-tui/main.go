package main

import (
	"bufio"
	"bytes"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"
	"unicode"
	"unicode/utf8"

	tea "github.com/charmbracelet/bubbletea"
)

const savedReplicasAnnotation = "homelab.tui/original-replicas"

type workload struct {
	kind       string
	name       string
	desired    int32
	ready      int32
	replicas   int32
	matchLabel map[string]string
}

type kubeItem struct {
	Kind     string `json:"kind"`
	Metadata struct {
		Name        string            `json:"name"`
		Annotations map[string]string `json:"annotations"`
	} `json:"metadata"`
	Spec struct {
		Replicas *int32 `json:"replicas"`
		Selector struct {
			MatchLabels map[string]string `json:"matchLabels"`
		} `json:"selector"`
	} `json:"spec"`
	Status struct {
		ReadyReplicas int32 `json:"readyReplicas"`
		Replicas      int32 `json:"replicas"`
	} `json:"status"`
}

type workloadList struct {
	Items []kubeItem `json:"items"`
}

type model struct {
	root        string
	namespace   string
	items       []workload
	selected    int
	width       int
	height      int
	busy        bool
	mode        string
	input       string
	inputCursor int
	confirm     string
	lastAction  string
	output      string
	progress    []string
	err         string
}

type workloadMsg struct {
	items []workload
	err   error
}

type commandMsg struct {
	label  string
	output string
	err    error
	reveal bool
}

type progressMsg struct{ line string }
type tickMsg time.Time

var activeProgram *tea.Program

func main() {
	namespace := flag.String("namespace", envOr("NAMESPACE", "homelab"), "Kubernetes namespace to manage")
	flag.Parse()
	root, err := findRoot()
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	activeProgram = tea.NewProgram(model{root: root, namespace: *namespace}, tea.WithAltScreen())
	if _, err := activeProgram.Run(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func envOr(key, fallback string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return fallback
}

func findRoot() (string, error) {
	if root := os.Getenv("HOMELAB_ROOT"); root != "" {
		return filepath.Abs(root)
	}
	wd, err := os.Getwd()
	if err != nil {
		return "", err
	}
	for dir := wd; ; dir = filepath.Dir(dir) {
		if _, err := os.Stat(filepath.Join(dir, "scripts", "deploy.sh")); err == nil {
			return dir, nil
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			return "", errors.New("could not locate homelab repo; run from the repo or set HOMELAB_ROOT")
		}
	}
}

func (m model) Init() tea.Cmd {
	return tea.Batch(loadWorkloads(m.namespace), scheduleRefresh(), func() tea.Msg {
		return tea.EnableBracketedPaste()
	})
}

func scheduleRefresh() tea.Cmd {
	return tea.Tick(8*time.Second, func(t time.Time) tea.Msg { return tickMsg(t) })
}

func loadWorkloads(namespace string) tea.Cmd {
	return func() tea.Msg {
		cmd := exec.Command("kubectl", "get", "deployments,statefulsets", "-n", namespace, "-o", "json")
		out, err := cmd.CombinedOutput()
		if err != nil {
			return workloadMsg{err: fmt.Errorf("kubectl get workloads: %w: %s", err, strings.TrimSpace(string(out)))}
		}
		var list workloadList
		if err := json.Unmarshal(out, &list); err != nil {
			return workloadMsg{err: err}
		}
		items := make([]workload, 0, len(list.Items))
		for _, item := range list.Items {
			kind := item.Kind
			if kind == "" {
				continue
			}
			desired := int32(1)
			if item.Spec.Replicas != nil {
				desired = *item.Spec.Replicas
			}
			items = append(items, workload{kind: kind, name: item.Metadata.Name, desired: desired,
				ready: item.Status.ReadyReplicas, replicas: item.Status.Replicas, matchLabel: item.Spec.Selector.MatchLabels})
		}
		sort.Slice(items, func(i, j int) bool {
			if items[i].kind == items[j].kind {
				return items[i].name < items[j].name
			}
			return items[i].kind < items[j].kind
		})
		return workloadMsg{items: items}
	}
}

func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width, m.height = msg.Width, msg.Height
	case workloadMsg:
		if msg.err != nil {
			m.err = msg.err.Error()
		} else {
			m.items = msg.items
			if m.selected >= len(m.items) {
				m.selected = max(0, len(m.items)-1)
			}
			m.err = ""
		}
	case commandMsg:
		m.busy = false
		m.lastAction = msg.label
		m.output = strings.TrimSpace(msg.output)
		if !msg.reveal {
			m.output = redact(m.output)
		}
		m.progress = nil
		if msg.err != nil {
			m.err = msg.err.Error()
		} else {
			m.err = ""
		}
		return m, tea.Batch(loadWorkloads(m.namespace), scheduleRefresh())
	case progressMsg:
		m.progress = append(m.progress, msg.line)
		if len(m.progress) > 6 {
			m.progress = m.progress[len(m.progress)-6:]
		}
	case tickMsg:
		if !m.busy && m.mode == "" {
			return m, tea.Batch(loadWorkloads(m.namespace), scheduleRefresh())
		}
		return m, scheduleRefresh()
	case tea.KeyMsg:
		if m.busy {
			if msg.String() == "ctrl+c" {
				return m, tea.Quit
			}
			return m, nil
		}
		if strings.HasPrefix(m.mode, "args-") {
			return m.updateArgs(msg)
		}
		if m.mode == "confirm" {
			switch msg.String() {
			case "y", "enter":
				label := m.confirm
				m.mode, m.confirm = "", ""
				if label == "reset-password" {
					return m.begin(m.resetUnslothPassword())
				}
				return m.begin(m.runSelected(label))
			case "n", "esc":
				m.mode, m.confirm = "", ""
			}
			return m, nil
		}
		switch msg.String() {
		case "q", "ctrl+c":
			return m, tea.Quit
		case "up", "k":
			if m.selected > 0 {
				m.selected--
			}
		case "down", "j":
			if m.selected < len(m.items)-1 {
				m.selected++
			}
		case "r":
			return m.begin(m.runSelected("restart"))
		case "d":
			m.confirm = "redeploy"
			m.mode = "confirm"
		case "s":
			m.confirm = "stop"
			m.mode = "confirm"
		case "a":
			return m.begin(m.runSelected("start"))
		case "x":
			m.confirm = "kill"
			m.mode = "confirm"
		case "P":
			m.confirm = "reset-password"
			m.mode = "confirm"
		case "M":
			m.mode, m.input, m.inputCursor = "args-ollama-pull", "", 0
		case "L":
			return m.begin(m.listOllamaModels())
		case "D":
			m.mode, m.input, m.inputCursor = "args-deploy", "", 0
		case "u", "U":
			m.mode, m.input, m.inputCursor = "args-update", "", 0
		case "R":
			return m, loadWorkloads(m.namespace)
		}
	}
	return m, nil
}

func (m model) updateArgs(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	if msg.Paste {
		var pasted strings.Builder
		for _, r := range msg.Runes {
			if r == '\n' || r == '\r' || r == '\t' {
				r = ' '
			}
			if unicode.IsControl(r) {
				continue
			}
			pasted.WriteRune(r)
			if pasted.Len() >= 8192 {
				break
			}
		}
		text := pasted.String()
		m.input = m.input[:m.inputCursor] + text + m.input[m.inputCursor:]
		m.inputCursor += len(text)
		return m, nil
	}
	switch msg.String() {
	case "esc":
		m.mode, m.input = "", ""
	case "enter":
		mode := m.mode
		m.mode = ""
		if mode == "args-ollama-pull" {
			return m.begin(m.pullOllamaModel(m.input))
		}
		return m.begin(m.runScript(mode, m.input))
	case "backspace", "ctrl+h":
		if m.inputCursor > 0 {
			previous := m.inputCursor - 1
			for previous > 0 && !utf8.RuneStart(m.input[previous]) {
				previous--
			}
			m.input = m.input[:previous] + m.input[m.inputCursor:]
			m.inputCursor = previous
		}
	case "delete":
		if m.inputCursor < len(m.input) {
			next := m.inputCursor + utf8.RuneLen([]rune(m.input[m.inputCursor:])[0])
			m.input = m.input[:m.inputCursor] + m.input[next:]
		}
	case "left":
		if m.inputCursor > 0 {
			m.inputCursor--
			for m.inputCursor > 0 && !utf8.RuneStart(m.input[m.inputCursor]) {
				m.inputCursor--
			}
		}
	case "right":
		if m.inputCursor < len(m.input) {
			m.inputCursor += utf8.RuneLen([]rune(m.input[m.inputCursor:])[0])
		}
	default:
		if len(msg.Runes) > 0 {
			var text strings.Builder
			for _, r := range msg.Runes {
				if !unicode.IsControl(r) {
					text.WriteRune(r)
				}
			}
			insert := text.String()
			m.input = m.input[:m.inputCursor] + insert + m.input[m.inputCursor:]
			m.inputCursor += len(insert)
		}
	}
	return m, nil
}

func (m model) runScript(mode, raw string) tea.Cmd {
	args, env, err := parseArgs(raw)
	if err != nil {
		return func() tea.Msg { return commandMsg{label: "Parse script arguments", err: err} }
	}
	script := "deploy.sh"
	label := "Full deploy"
	if mode == "args-update" {
		script, label = "update.sh", "Full update"
	}
	cmdArgs := append([]string{filepath.Join(m.root, "scripts", script)}, args...)
	return m.command(label, cmdArgs, env)
}

var modelNamePattern = regexp.MustCompile(`^[[:graph:]]{1,256}$`)

func (m model) listOllamaModels() tea.Cmd {
	return m.command("List Ollama models", []string{"kubectl", "exec", "-n", m.namespace, "deploy/ollama", "--", "ollama", "list"}, nil)
}

func (m model) pullOllamaModel(raw string) tea.Cmd {
	name := strings.TrimSpace(raw)
	if !modelNamePattern.MatchString(name) || strings.ContainsAny(name, "'\"\\") {
		return errorCmd("Install Ollama model", "enter one model name, for example gemma3:4b or hf.co/owner/model:tag")
	}
	root, namespace := m.root, m.namespace
	return func() tea.Msg {
		cmd := exec.Command("kubectl", "exec", "-n", namespace, "deploy/ollama", "--", "ollama", "pull", name)
		cmd.Dir = root
		stdout, err := cmd.StdoutPipe()
		if err != nil {
			return commandMsg{label: "Install Ollama model " + name, err: err}
		}
		stderr, err := cmd.StderrPipe()
		if err != nil {
			return commandMsg{label: "Install Ollama model " + name, err: err}
		}
		if err := cmd.Start(); err != nil {
			return commandMsg{label: "Install Ollama model " + name, err: err}
		}
		var mu sync.Mutex
		lines := make([]string, 0, 16)
		var wg sync.WaitGroup
		scan := func(scanner *bufio.Scanner) {
			defer wg.Done()
			scanner.Split(splitProgressLines)
			for scanner.Scan() {
				line := strings.TrimSpace(scanner.Text())
				if line == "" {
					continue
				}
				mu.Lock()
				lines = append(lines, line)
				if len(lines) > 24 {
					lines = lines[len(lines)-24:]
				}
				mu.Unlock()
				if activeProgram != nil {
					activeProgram.Send(progressMsg{line: line})
				}
			}
		}
		wg.Add(2)
		go scan(bufio.NewScanner(stdout))
		go scan(bufio.NewScanner(stderr))
		wg.Wait()
		waitErr := cmd.Wait()
		mu.Lock()
		output := strings.Join(lines, "\n")
		mu.Unlock()
		if waitErr != nil {
			return commandMsg{label: "Install Ollama model " + name, output: output, err: waitErr}
		}
		return commandMsg{label: "Install Ollama model " + name, output: output}
	}
}

func (m model) resetUnslothPassword() tea.Cmd {
	root, namespace := m.root, m.namespace
	return func() tea.Msg {
		cmd := exec.Command(filepath.Join(root, "scripts", "reset-unsloth-password.sh"))
		cmd.Dir = root
		cmd.Env = overlayEnv(os.Environ(), map[string]string{"NAMESPACE": namespace})
		out, err := cmd.CombinedOutput()
		if err != nil {
			return commandMsg{label: "Reset Unsloth Studio password", output: redact(string(out)), err: err}
		}
		return commandMsg{label: "Reset Unsloth Studio password", output: strings.TrimSpace(string(out)), reveal: true}
	}
}

func splitProgressLines(data []byte, atEOF bool) (advance int, token []byte, err error) {
	if index := bytes.IndexAny(data, "\r\n"); index >= 0 {
		advance = index + 1
		if data[index] == '\r' && advance < len(data) && data[advance] == '\n' {
			advance++
		}
		return advance, data[:index], nil
	}
	if atEOF && len(data) > 0 {
		return len(data), data, nil
	}
	return 0, nil, nil
}

func (m model) runSelected(action string) tea.Cmd {
	if len(m.items) == 0 {
		return nil
	}
	item := m.items[m.selected]
	resource := strings.ToLower(item.kind) + "/" + item.name
	switch action {
	case "restart":
		selector := labelSelector(item.matchLabel)
		if selector == "" {
			return errorCmd("Restart "+item.name, "workload has no matchLabels selector")
		}
		return m.command("Restart "+item.name, []string{"kubectl", "delete", "pods", "-n", m.namespace, "-l", selector, "--wait=true"}, nil)
	case "redeploy":
		return m.command("Redeploy "+item.name, []string{"kubectl", "rollout", "restart", resource, "-n", m.namespace}, nil,
			[]string{"kubectl", "rollout", "status", resource, "-n", m.namespace, "--timeout=180s"})
	case "stop":
		return m.command("Stop "+item.name, stopArgs(m.namespace, item), nil)
	case "start":
		return m.command("Start "+item.name, startArgs(m.namespace, item), nil)
	case "kill":
		selector := labelSelector(item.matchLabel)
		if selector == "" {
			return errorCmd("Force kill "+item.name, "workload has no matchLabels selector")
		}
		return m.command("Force kill pods for "+item.name,
			[]string{"kubectl", "delete", "pods", "-n", m.namespace, "-l", selector, "--grace-period=0", "--force", "--wait=false"}, nil)
	}
	return nil
}

func errorCmd(label, message string) tea.Cmd {
	return func() tea.Msg { return commandMsg{label: label, err: errors.New(message)} }
}

func stopArgs(namespace string, item workload) []string {
	resource := strings.ToLower(item.kind) + "/" + item.name
	current := item.desired
	if current < 1 {
		current = 1
	}
	return []string{"python3", "-c", stopPython, namespace, resource, strconv.Itoa(int(current))}
}

func startArgs(namespace string, item workload) []string {
	resource := strings.ToLower(item.kind) + "/" + item.name
	return []string{"python3", "-c", startPython, namespace, resource}
}

const startPython = `import json, subprocess, sys
ns, resource = sys.argv[1:]
obj = json.loads(subprocess.check_output(["kubectl", "get", "-n", ns, resource, "-o", "json"]))
ann = obj.get("metadata", {}).get("annotations", {})
replicas = ann.get("` + savedReplicasAnnotation + `", "1")
subprocess.check_call(["kubectl", "scale", "-n", ns, resource, "--replicas=" + replicas])
if "` + savedReplicasAnnotation + `" in ann:
    subprocess.check_call(["kubectl", "annotate", "-n", ns, resource, "` + savedReplicasAnnotation + `-"])
`

const stopPython = `import subprocess, sys
ns, resource, replicas = sys.argv[1:]
subprocess.check_call(["kubectl", "annotate", "-n", ns, resource, "` + savedReplicasAnnotation + `=" + replicas, "--overwrite"])
subprocess.check_call(["kubectl", "scale", "-n", ns, resource, "--replicas=0"])
`

func labelSelector(labels map[string]string) string {
	keys := make([]string, 0, len(labels))
	for key := range labels {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	pairs := make([]string, 0, len(keys))
	for _, key := range keys {
		pairs = append(pairs, key+"="+labels[key])
	}
	return strings.Join(pairs, ",")
}

func (m model) command(label string, first []string, env map[string]string, follow ...[]string) tea.Cmd {
	if len(first) == 0 {
		return nil
	}
	root, namespace := m.root, m.namespace
	return func() tea.Msg {
		var output bytes.Buffer
		all := [][]string{first}
		all = append(all, follow...)
		for _, args := range all {
			cmd := exec.Command(args[0], args[1:]...)
			cmd.Dir = root
			envValues := map[string]string{"NAMESPACE": namespace}
			for key, value := range env {
				envValues[key] = value
			}
			cmd.Env = overlayEnv(os.Environ(), envValues)
			var part bytes.Buffer
			cmd.Stdout, cmd.Stderr = &part, &part
			err := cmd.Run()
			output.WriteString("$ " + safeCommand(args, env) + "\n")
			output.WriteString(part.String())
			if err != nil {
				return commandMsg{label: label, output: redact(output.String()), err: err}
			}
		}
		return commandMsg{label: label, output: redact(output.String())}
	}
}

func (m model) begin(cmd tea.Cmd) (tea.Model, tea.Cmd) {
	if cmd != nil {
		m.busy = true
		m.lastAction = "Command running"
		m.output = ""
		m.err = ""
	}
	return m, cmd
}

func safeCommand(args []string, env map[string]string) string {
	parts := make([]string, len(args))
	for i, arg := range args {
		parts[i] = strconv.Quote(arg)
	}
	keys := make([]string, 0, len(env))
	for key := range env {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	for _, key := range keys {
		parts = append([]string{key + "=<set>"}, parts...)
	}
	return strings.Join(parts, " ")
}

func overlayEnv(base []string, overrides map[string]string) []string {
	values := make(map[string]string, len(base)+len(overrides))
	for _, entry := range base {
		key, value, ok := strings.Cut(entry, "=")
		if ok {
			values[key] = value
		}
	}
	for key, value := range overrides {
		values[key] = value
	}
	keys := make([]string, 0, len(values))
	for key := range values {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	env := make([]string, 0, len(keys))
	for _, key := range keys {
		env = append(env, key+"="+values[key])
	}
	return env
}

var secretLine = regexp.MustCompile(`(?im)^([^\n]*(?:password|secret|token|api[_-]?key)[^:=]*[:=]\s*).+$`)

func redact(text string) string {
	return secretLine.ReplaceAllString(text, `${1}<redacted>`)
}

func parseArgs(raw string) ([]string, map[string]string, error) {
	words, err := splitWords(raw)
	if err != nil {
		return nil, nil, err
	}
	assign := regexp.MustCompile(`^[A-Za-z_][A-Za-z0-9_]*=`)
	args, env := []string{}, map[string]string{}
	for _, word := range words {
		if assign.MatchString(word) {
			parts := strings.SplitN(word, "=", 2)
			env[parts[0]] = parts[1]
		} else {
			args = append(args, word)
		}
	}
	return args, env, nil
}

func splitWords(input string) ([]string, error) {
	var words []string
	var b strings.Builder
	quote := rune(0)
	escaped, active := false, false
	for _, r := range input {
		if escaped {
			b.WriteRune(r)
			escaped, active = false, true
			continue
		}
		if r == '\\' && quote != '\'' {
			escaped, active = true, true
			continue
		}
		if quote != 0 {
			if r == quote {
				quote = 0
			} else {
				b.WriteRune(r)
			}
			active = true
			continue
		}
		if r == '\'' || r == '"' {
			quote, active = r, true
			continue
		}
		if r == ' ' || r == '\t' || r == '\n' {
			if active {
				words = append(words, b.String())
				b.Reset()
				active = false
			}
			continue
		}
		b.WriteRune(r)
		active = true
	}
	if escaped || quote != 0 {
		return nil, errors.New("unfinished quote or escape in arguments")
	}
	if active {
		words = append(words, b.String())
	}
	return words, nil
}

func inputWindow(input string, cursor, width int) (before, current, after string) {
	cursor = min(cursor, len(input))
	position := utf8.RuneCountInString(input[:cursor])
	runes := []rune(input)
	visible := 72
	if width > 0 {
		visible = max(12, width-8)
	}
	start := max(0, position-visible+1)
	end := min(len(runes), start+visible)
	if start > 0 {
		before = "…"
	}
	before += string(runes[start:position])
	current = " "
	if position < len(runes) {
		current = string(runes[position])
	}
	if position+1 < end {
		after = string(runes[position+1 : end])
	}
	if end < len(runes) {
		after += "…"
	}
	return before, current, after
}

func (m model) View() string {
	var b strings.Builder
	title := "Homelab Control"
	fmt.Fprintf(&b, "\033[1;36m%s\033[0m  namespace: %s\n", title, m.namespace)
	b.WriteString("Manage Kubernetes deployments and statefulsets. Refreshes every 8s.\n\n")
	if m.mode == "args" || strings.HasPrefix(m.mode, "args-") {
		if m.mode == "args-ollama-pull" {
			b.WriteString("Ollama model name to install (example: gemma3:4b or hf.co/owner/model:tag):\n")
		} else {
			b.WriteString("Script arguments (space separated; quote values with spaces; KEY=VALUE sets an environment variable):\n")
		}
		before, current, after := inputWindow(m.input, m.inputCursor, m.width)
		fmt.Fprintf(&b, "> %s\033[7m%s\033[0m%s\n\nEnter runs, Esc cancels. No shell expansion is performed.\n", before, current, after)
		return b.String()
	}
	if m.mode == "confirm" {
		message := ""
		switch m.confirm {
		case "stop":
			message = "Stop the selected workload (scale replicas to zero)?"
		case "kill":
			message = "Force-delete its pods now? The workload controller will recreate them."
		case "redeploy":
			message = "Roll the workload using its current Kubernetes spec? Persistent volumes are preserved."
		case "reset-password":
			message = "Reset the Unsloth Studio password? The new password will be shown here and saved locally."
		}
		fmt.Fprintf(&b, "Confirm: %s [y/N]\n\n", message)
	} else {
		fmt.Fprintf(&b, "%-20s %-14s %s\n", "WORKLOAD", "READY", "STATUS")
		limit := max(5, m.height-13)
		start := 0
		if m.selected >= limit {
			start = m.selected - limit + 1
		}
		end := min(len(m.items), start+limit)
		for i := start; i < end; i++ {
			item := m.items[i]
			cursor := "  "
			if i == m.selected {
				cursor = "› "
			}
			status := "Running"
			if item.desired == 0 {
				status = "Stopped"
			} else if item.ready < item.desired {
				status = "Progressing"
			}
			name := item.kind + "/" + item.name
			if len(name) > 19 {
				name = name[:19]
			}
			fmt.Fprintf(&b, "%s%-20s %-14s %s\n", cursor, name, fmt.Sprintf("%d/%d", item.ready, item.desired), status)
		}
		if len(m.items) == 0 {
			b.WriteString("No deployments or statefulsets found. Check kubectl and namespace.\n")
		}
		b.WriteString("\n")
		b.WriteString("↑/↓ select  r restart pods  d redeploy from current spec  s stop  a start  x force kill pods\n")
		b.WriteString("D full deploy (args)  u update (args)  P reset Unsloth password\n")
		b.WriteString("M install Ollama model  L list Ollama models  R refresh  q quit\n")
	}
	if m.busy {
		fmt.Fprintf(&b, "\nRunning: %s…\n", m.lastAction)
		for _, line := range m.progress {
			fmt.Fprintf(&b, "  %s\n", line)
		}
	}
	if m.lastAction != "" {
		fmt.Fprintf(&b, "\nLast action: %s\n", m.lastAction)
	}
	if m.err != "" {
		fmt.Fprintf(&b, "\033[1;31mError: %s\033[0m\n", m.err)
	}
	if m.output != "" {
		lines := strings.Split(m.output, "\n")
		if len(lines) > 8 {
			lines = lines[len(lines)-8:]
		}
		b.WriteString("\n")
		b.WriteString(strings.Join(lines, "\n"))
	}
	return b.String()
}
