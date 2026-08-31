import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

Item {
  id: root

  property var settings: ({})

  // ── Backend selection ────────────────────────────────────────────────
  property string backend: "ollama"  // "ollama" | "llama.cpp"

  readonly property string backendDisplayName: backend === "llama.cpp" ? "llama.cpp" : "ollama"
  readonly property string backendBinary: backend === "llama.cpp" ? "llama-server" : "ollama"
  readonly property string backendService: backend === "llama.cpp" ? "llama.cpp.service" : "ollama.service"
  readonly property var backendDebugArgs: backend === "llama.cpp"
    ? ["journalctl", "--user", "-u", "llama.cpp.service", "-f"]
    : ["journalctl", "-u", "ollama.service", "-f"]
  readonly property int backendPort: backend === "llama.cpp" ? 8080 : 11434
  readonly property string backendHealthEndpoint: backend === "llama.cpp" ? "http://127.0.0.1:8080/health" : "http://127.0.0.1:11434/"
  // llama.cpp self-provisions its env file and user systemd unit on start
  // (no root/polkit); ollama is managed via the system instance + JSON config.
  readonly property bool selfManaged: backend === "llama.cpp"

  // ── Per-backend config file ─────────────────────────────────────────
  // ollama uses a JSON config in the plugin `configs/` directory, written
  // on user request via a password prompt. llama.cpp uses a user-editable
  // env file (`configs/llama.env`) read by its user systemd unit via
  // EnvironmentFile=; it is self-provisioned on start. The settings button
  // in Dashboard.qml opens `configPath` in the user's editor.
  readonly property string backendConfigFile: backend === "llama.cpp" ? "llama.env" : "ollama.json"
  readonly property string configPath: Qt.resolvedUrl("configs/" + backendConfigFile).toString().replace(/^file:\/\//, "")
  readonly property string defaultConfigJson: '{"host":"127.0.0.1","port":11434,"api-key":""}'
  // Default llama.cpp env file. Written via an unquoted heredoc so $HOME
  // expands to the absolute preset path at write time (systemd does no
  // tilde/var expansion inside env files).
  readonly property string llamaEnvDefault: '# llama.cpp server configuration\n# Managed by local-ai-dashboard. Edit values, then start/restart from the panel.\nLLAMA_HOST=127.0.0.1\nLLAMA_PORT=8080\nLLAMA_API_KEY=\nLLAMA_MODELS_PRESET="$HOME/.config/llama.cpp/models.ini"\nLLAMA_MODELS_MAX=1\nLLAMA_EXTRA_ARGS=\n'

  property string configHost: "127.0.0.1"
  property int configPort: 0
  property string configApiKey: ""

  readonly property string effectiveHost: configHost !== "" ? configHost : "127.0.0.1"
  readonly property int effectivePort: configPort > 0 ? configPort : backendPort
  readonly property string effectiveHealthEndpoint: "http://" + effectiveHost + ":" + effectivePort + (backend === "llama.cpp" ? "/health" : "/")

  // curl auth header for the API, only sent when an api-key is configured.
  readonly property string apiKeyCurlHeader: {
    if (configApiKey === "") return ""
    var safe = String(configApiKey).replace(/'/g, "'\\''")
    return backend === "llama.cpp"
      ? " -H 'X-Api-Key: " + safe + "'"
      : " -H 'Authorization: Bearer " + safe + "'"
  }

  // ── State ─────────────────────────────────────────────────────────
  property bool installed: false       // backend binary on PATH
  property bool hasService: false      // systemd unit file exists
  property bool running: false
  property bool busy: false
  property bool hasConfig: false       // plugin config file exists
  property string actionLabel: ""
  property string lastError: ""

  // ── API health ─────────────────────────────────────────────────────
  property bool apiReachable: false
  property int apiLatencyMs: -1

  // ── Model info (bounded) ──────────────────────────────────────────
  readonly property int maxModels: 50
  readonly property int maxRunning: 10
  property var models: []
  property var runningModels: []

  // ── Service info ───────────────────────────────────────────────────
  property string activeSince: ""
  property string ollamaVersion: ""
  property double serviceMemoryBytes: -1  // llama.cpp DRAM: cgroup anon+shmem working set (bytes); double avoids 32-bit int overflow >2 GiB
  property double serviceVramBytes: -1    // llama.cpp VRAM: per-PID GPU memory (bytes); -1 = unknown
  property double serviceTotalBytes: -1   // llama.cpp full footprint = DRAM + VRAM; -1 = unknown

  // ── Refresh ────────────────────────────────────────────────────────
  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 10, 2, 300)

  // ── Process deadlines ─────────────────────────────────────────────
  //
  // Two layers of deadline protection:
  //
  // 1. `timeout` (primary): runs each command in its own process group
  //    and kills the entire group on expiry — no orphaned children.
  //    `timeout -k 2 N` sends SIGTERM after N seconds, then SIGKILL 2s
  //    later if still running. Exit code 124 (timeout) or 137 (SIGKILL)
  //    is discarded by the exitCode === 0 guard in onExited.
  //
  // 2. QML watchdog (backup): if timeout itself somehow hangs, the
  //    watchdog sets process.running = false, which calls
  //    QProcess::terminate() on the timeout PID. This is a fallback only.
  //
  // The watchdog interval is set slightly above the timeout duration so
  // timeout (which handles the process group) always fires first.

  readonly property int processTimeoutSec: 8       // timeout duration for regular commands
  readonly property int startTimeoutSec: 15        // systemctl start can be slow
  readonly property int watchdogMs: 12000          // backup watchdog for regular commands
  readonly property int startWatchdogMs: 20000     // backup watchdog for start

  // ── Output caps at the OS pipe level ──────────────────────────────
  // Every command is piped through `head -c N` so the producer cannot
  // force unbounded allocation in SplitParser's internal line buffer.
  // `set -o pipefail` preserves the producer's exit code; SIGPIPE from
  // head truncation yields exit 141, which our exitCode === 0 guard
  // discards so truncated output is never parsed.
  readonly property int capService: 2048     // systemctl show output
  readonly property int capCheck: 512       // systemctl list-unit-files output
  readonly property int capList: 65536      // model list output
  readonly property int capPs: 16384       // running models output
  readonly property int capVersion: 256    // version output
  readonly property int capApi: 128        // API health check output
  readonly property int capAction: 512     // start/stop stderr capture
  readonly property int capConfig: 2048    // config file read output
  readonly property int capServiceMemory: 64  // memory.stat anon+shmem sum (bytes)
  readonly property int capServiceVram: 64    // nvidia-smi/rocm-smi per-PID value

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function intSetting(name, fallback, min, max) {
    var n = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(n)) n = fallback
    if (n < min) n = min
    if (n > max) n = max
    return n
  }

  // ── Sanitize external strings for safe display ──────────────────────
  function formatGB(bytes) {
    var b = parseInt(String(bytes), 10)
    if (!isFinite(b) || b < 0) return "\u2014"
    var gb = b / (1024 * 1024 * 1024)
    if (gb >= 1024) return (gb / 1024).toFixed(1) + " TB"
    return gb.toFixed(1) + " GB"
  }

  // CPU/GPU split (llama.cpp): CPU = measured DRAM fraction of the full
  // footprint (DRAM + per-PID VRAM); GPU covers the remainder. Both halves
  // are measured — no size-based estimate. Returns CPU percent, or -1 when
  // either measurement is unavailable.
  function cpuSplitPercent() {
    if (serviceTotalBytes < 0) return -1
    return Math.round(serviceMemoryBytes / serviceTotalBytes * 100)
  }

  // Full llama.cpp memory footprint (DRAM + VRAM) formatted for display,
  // or "" when unknown.
  function memoryTotalGB() {
    return serviceTotalBytes >= 0 ? formatGB(serviceTotalBytes) : ""
  }

  function sanitize(str) {
    return String(str || "").replace(/[<>&]/g, function(c) {
      if (c === "<") return "&lt;"
      if (c === ">") return "&gt;"
      if (c === "&") return "&amp;"
      return c
    })
  }

  function truncate(str, maxLen) {
    var s = String(str || "")
    if (s.length <= maxLen) return s
    return s.substring(0, maxLen) + "…"
  }

  // Classify a start/stop failure into an actionable message.
  //
  // Start/stop goes through `pkexec /usr/bin/systemctl …`, which shows a graphical
  // polkit prompt (Omarchy ships a polkit agent inside omarchy-shell).
  // Detect the common failure modes — cancelled prompt, no polkit agent,
  // explicit denial — and surface actionable text instead of raw output.
  function _actionError(output, verb) {
    var s = String(output || "").trim()
    var verbDisplay = verb === "start" ? "Start" : verb === "create" ? "Create" : "Stop"
    if (/request dismissed|dismissed by user|was not shown|cancelled|canceled/i.test(s)) {
      return verbDisplay + " cancelled — authentication was dismissed."
    }
    if (/not authorized|permission denied|access denied/i.test(s)) {
      return "Cannot " + verb + " " + root.backendDisplayName + ": you are not authorized to manage system services."
    }
    if (/no authentication agent|error creating textual authentication agent/i.test(s)) {
      return "Cannot " + verb + " " + root.backendDisplayName + ": no polkit authentication agent found.\n" +
             "Make sure the Polkit plugin is enabled in omarchy-shell settings."
    }
    return "Failed to " + verb + " " + root.backendDisplayName
  }

  // ── Process management ──────────────────────────────────────────────
  function launch(process, watchdog) {
    if (!process.running) {
      process.running = true
      watchdog.restart()
    }
  }

  function reap(process, watchdog) {
    watchdog.stop()
    if (process.running) process.running = false
  }

  function refresh() {
    if (!installed) {
      launch(whichProcess, whichWatchdog)
      return
    }
    if (!hasService) {
      launch(checkServiceProcess, checkServiceWatchdog)
      return
    }
    launch(serviceProcess, serviceWatchdog)
  }

  function refreshApi() {
    if (!running) {
      apiReachable = false
      apiLatencyMs = -1
      return
    }
    // Clear transient errors on a fresh successful refresh cycle
    lastError = ""
    launch(apiHealthProcess, apiHealthWatchdog)
    launch(listProcess, listWatchdog)
    launch(psProcess, psWatchdog)
    // llama.cpp: query the user service's current DRAM + VRAM footprint
    if (backend === "llama.cpp") {
      launch(serviceMemoryProcess, serviceMemoryWatchdog)
      launch(serviceVramProcess, serviceVramWatchdog)
    }
    // Only fetch version once — it never changes during a session
    if (ollamaVersion === "" && !versionProcess.running) {
      launch(versionProcess, versionWatchdog)
    }
  }

  function startService() {
    // Start: llama.cpp self-provisions env + unit, so only needs the binary installed.
    if (busy || !installed) return
    if (backend === "ollama" && (!hasService || !hasConfig)) return
    busy = true
    actionLabel = "Starting " + root.backendDisplayName + "…"
    lastError = ""
    startProcess.running = true
    startActionWatchdog.restart()
  }

  function stopService() {
    // Stop: llama.cpp needs its user unit to exist.
    if (busy || !installed) return
    if (backend === "ollama" && (!hasService || !hasConfig)) return
    if (backend === "llama.cpp" && !hasService) return
    busy = true
    actionLabel = "Stopping " + root.backendDisplayName + "…"
    lastError = ""
    stopProcess.running = true
    stopActionWatchdog.restart()
  }

  // Write the default config file: a password prompt for ollama, plain bash
  // for llama.cpp. Guarded by `!hasConfig` so an existing file is never
  // overwritten; on success the file is re-read so the config values and
  // hasConfig update immediately.
  function createConfigFile() {
    if (busy || hasConfig) return
    busy = true
    actionLabel = "Creating " + root.backendDisplayName + " config…"
    lastError = ""
    createConfigProcess.running = true
    createConfigWatchdog.restart()
  }

  function toggleService() {
    if (running) stopService()
    else startService()
  }

  // ── Streaming parsers ──────────────────────────────────────────────
  //
  // Output is bounded at the OS pipe level by `head -c N` (see cap*
  // properties above).  SplitParser then hands each line to onRead as it
  // arrives.  These parsers cap their own accumulation and the arrays
  // they feed as a second layer of defence.

  // systemctl show → service state
  property string _serviceBuffer: ""
  readonly property int _serviceBufferMax: 2048

  function _onServiceLine(line) {
    var s = String(line || "")
    if (_serviceBuffer.length + s.length + 1 <= _serviceBufferMax) {
      _serviceBuffer += s + "\n"
    }
  }

  function _parseServiceBuffer() {
    var raw = _serviceBuffer
    _serviceBuffer = ""
    var lines = raw.trim().split("\n").slice(0, 20)
    var state = ""
    var subState = ""
    var since = ""
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i]
      if (line.indexOf("ActiveState=") === 0) state = truncate(line.substring(12), 64)
      else if (line.indexOf("SubState=") === 0) subState = truncate(line.substring(9), 64)
      else if (line.indexOf("ActiveEnterTimestamp=") === 0) since = truncate(line.substring(21), 128)
    }
    running = (state === "active" && subState === "running")
    activeSince = since
    if (running) refreshApi()
    else {
      runningModels = []
      apiReachable = false
      apiLatencyMs = -1
      serviceMemoryBytes = -1
      serviceVramBytes = -1
      serviceTotalBytes = -1
    }
  }

  // systemctl list-unit-files → service existence
  property string _checkBuffer: ""
  readonly property int _checkBufferMax: 512

  function _onCheckLine(line) {
    var s = String(line || "")
    if (_checkBuffer.length + s.length + 1 <= _checkBufferMax) {
      _checkBuffer += s + "\n"
    }
  }

  function _parseCheckBuffer() {
    var output = truncate(_checkBuffer.trim(), 512)
    _checkBuffer = ""
    hasService = output.length > 0 && output.indexOf(root.backendService) !== -1
    if (hasService) refresh()
  }

  // ollama list → model list (tabular format)
  property var _listModels: []
  property bool _listHeaderSeen: false

  function _onListLine(line) {
    if (_listModels.length >= maxModels) return
    var s = String(line || "").trim()
    if (s === "") return
    if (!_listHeaderSeen) { _listHeaderSeen = true; return }
    var parts = s.split(/\s{2,}/)
    if (parts.length >= 4) {
      var name = truncate(parts[0] || "", 128)
      _listModels.push({
        name: name,
        id: truncate(parts[1] || "", 64),
        size: truncate(parts[2] || "", 32),
        modified: truncate(parts.slice(3).join("  ") || "", 64),
        isCloud: isCloudModel(name)
      })
    }
  }

  function _finishList() {
    models = _listModels
    _listModels = []
    _listHeaderSeen = false
  }

  // llama.cpp /v1/models → model list (JSON format)
  property string _jsonBuffer: ""
  readonly property int _jsonBufferMax: 65536

  function _onJsonLine(line) {
    var s = String(line || "")
    if (_jsonBuffer.length + s.length + 1 <= _jsonBufferMax) {
      _jsonBuffer += s + "\n"
    }
  }

  function _finishJsonModels() {
    var raw = _jsonBuffer.trim()
    _jsonBuffer = ""
    try {
      var obj = JSON.parse(raw)
      var data = obj.data || []
      _listModels = []
      _psModels = []
      for (var i = 0; i < data.length && _psModels.length < maxRunning; i++) {
        var m = data[i]
        if (m.status && m.status.value === "loaded") {
          var loadedName = m.id || "Unknown model"
          var pathParts = String(loadedName).split("/")
          var sizeBytes = parseInt(m.meta && m.meta.size, 10)
          if (!isFinite(sizeBytes) || sizeBytes < 0) sizeBytes = 0
          _psModels.push({
            name: truncate(pathParts[pathParts.length - 1] || "Unknown model", 128),
            id: truncate(m.id || "", 64),
            size: sizeBytes > 0 ? root.formatGB(sizeBytes) : "",
            sizeBytes: sizeBytes,
            processor: truncate(m.status.processor || m.status.backend || "CPU", 32),
            context: truncate(m.status.context || "", 32),
            until: "loaded"
          })
        }
        _listModels.push({
          name: truncate(m.id || "", 128),
          id: truncate(m.id || "", 64),
          size: "",
          modified: "",
          isCloud: false
        })
      }
    } catch(e) {
      _listModels = []
      _psModels = []
    }
    models = _listModels
    runningModels = _psModels
    _psModels = []
    _listHeaderSeen = false
  }

  // ollama ps → running models
  property var _psModels: []
  property bool _psHeaderSeen: false

  function _onPsLine(line) {
    if (_psModels.length >= maxRunning) return
    var s = String(line || "").trim()
    if (s === "") return
    if (!_psHeaderSeen) { _psHeaderSeen = true; return }
    var parts = s.split(/\s{2,}/)
    if (parts.length >= 2) {
      _psModels.push({
        name: truncate(parts[0] || "", 128),
        id: truncate(parts[1] || "", 64),
        size: truncate(parts[2] || "", 32),
        processor: truncate(parts[3] || "", 32),
        context: truncate(parts[4] || "", 32),
        until: truncate(parts.slice(5).join("  ") || "", 64)
      })
    }
  }

  function _finishPs() {
    if (root.backend === "llama.cpp") return
    runningModels = _psModels
    _psModels = []
    _psHeaderSeen = false
  }

  // llama.cpp running models: pgrep → extract --model / -m argument
  property string _pgrepBuffer: ""
  readonly property int _pgrepBufferMax: 512

  function _onPgrepLine(line) {
    var s = String(line || "")
    if (_pgrepBuffer.length + s.length + 1 <= _pgrepBufferMax) {
      _pgrepBuffer += s + "\n"
    }
  }

  function _finishPgrep() {
    var raw = _pgrepBuffer.trim()
    _pgrepBuffer = ""
    var lines = raw === "" ? [] : raw.split("\n")
    _psModels = []
    for (var i = 0; i < lines.length && _psModels.length < maxRunning; i++) {
      var match = String(lines[i]).trim().match(/(?:--model|-m)[= ]+([^ ]+)/)
      if (!match) continue
      var path = match[1]
      var name = path.split("/").pop()
      _psModels.push({
        name: truncate(name || "Unknown model", 128),
        id: "local",
        size: "",
        processor: "CPU",
        context: "",
        until: "loaded"
      })
    }
    _psHeaderSeen = false
  }

  // ollama --version → version string (only fetched once per session)
  function _onVersionLine(line) {
    if (ollamaVersion === "") {
      var v = String(line || "").trim()
      if (backend === "llama.cpp") {
        v = v.replace(/,\s*commit\s+[^\s)]+/, "").trim()
      }
      ollamaVersion = truncate(v, 128)
    }
  }

  // API health → latency
  property string _apiBuffer: ""
  readonly property int _apiBufferMax: 128

  function _onApiLine(line) {
    var s = String(line || "")
    if (_apiBuffer.length + s.length + 1 <= _apiBufferMax) {
      _apiBuffer += s + "\n"
    }
  }

  function _parseApiBuffer() {
    var raw = truncate(_apiBuffer.trim(), 128)
    _apiBuffer = ""
    var parts = raw.split(/\s+/)
    var code = parseInt(parts[0], 10)
    var latency = parseInt(parts[1], 10)
    apiReachable = (code === 200)
    apiLatencyMs = isFinite(latency) && latency >= 0 ? latency : -1
  }

  // cgroup memory.stat (anon + shmem) → llama.cpp DRAM working set (bytes), excluding reclaimable page cache
  property string _serviceMemoryBuffer: ""
  readonly property int _serviceMemoryBufferMax: 64

  function _onServiceMemoryLine(line) {
    var s = String(line || "")
    if (_serviceMemoryBuffer.length + s.length + 1 <= _serviceMemoryBufferMax) {
      _serviceMemoryBuffer += s + "\n"
    }
  }

  function _finishServiceMemory() {
    var raw = truncate(_serviceMemoryBuffer.trim(), _serviceMemoryBufferMax)
    _serviceMemoryBuffer = ""
    var n = parseInt(raw.split("\n")[0], 10)
    serviceMemoryBytes = isFinite(n) && n >= 0 ? n : -1
    _deriveServiceTotal()
  }

  // nvidia-smi/rocm-smi → llama.cpp per-PID VRAM footprint
  property string _serviceVramBuffer: ""
  readonly property int _serviceVramBufferMax: 64

  function _onServiceVramLine(line) {
    var s = String(line || "")
    if (_serviceVramBuffer.length + s.length + 1 <= _serviceVramBufferMax) {
      _serviceVramBuffer += s + "\n"
    }
  }

  function _finishServiceVram() {
    var raw = truncate(_serviceVramBuffer.trim(), _serviceVramBufferMax)
    _serviceVramBuffer = ""
    // The query emits the "used_memory" column (e.g. "64 MiB"); any sentinel
    // (empty / non-numeric / "N/A") means no measurable GPU context → unknown.
    var m = raw.match(/(\d+(?:\.\d+)?)\s*MiB/)
    var n = m ? Math.round(parseFloat(m[1]) * 1024 * 1024) : -1
    serviceVramBytes = n >= 0 ? n : -1
    _deriveServiceTotal()
  }

  // Full footprint = measured DRAM + measured per-PID VRAM. Unknown when
  // either half hasn't resolved.
  function _deriveServiceTotal() {
    if (serviceMemoryBytes >= 0 && serviceVramBytes >= 0) {
      serviceTotalBytes = serviceMemoryBytes + serviceVramBytes
    } else {
      serviceTotalBytes = -1
    }
  }

  // ── Config file → JSON → state ──────────────────────────────────────
  property string _configBuffer: ""
  readonly property int _configBufferMax: 2048

  function _onConfigLine(line) {
    var s = String(line || "")
    if (_configBuffer.length + s.length + 1 <= _configBufferMax) {
      _configBuffer += s + "\n"
    }
  }

  function _parseConfigBuffer() {
    var raw = truncate(_configBuffer.trim(), _configBufferMax)
    _configBuffer = ""
    var newline = raw.indexOf("\n")
    var first = newline !== -1 ? raw.substring(0, newline).trim() : raw
    var body = newline !== -1 ? raw.substring(newline + 1) : ""
    hasConfig = first === "HAS"
    if (!hasConfig) {
      configHost = "127.0.0.1"
      configPort = 0
      configApiKey = ""
      return
    }
    if (backend === "llama.cpp") {
      var host = "127.0.0.1"
      var port = 0
      var apiKey = ""
      var envLines = body.split("\n")
      for (var i = 0; i < envLines.length; i++) {
        var line = String(envLines[i]).replace(/^\s+|\s+$/g, "")
        if (line === "" || line.charAt(0) === "#") continue
        var eq = line.indexOf("=")
        if (eq === -1) continue
        var key = line.substring(0, eq).replace(/^\s+|\s+$/g, "")
        var val = line.substring(eq + 1).replace(/^\s+|\s+$/g, "").replace(/^"(.*)"$/, "$1")
        if (key === "LLAMA_HOST") host = val !== "" ? val : "127.0.0.1"
        else if (key === "LLAMA_PORT") {
          var p = parseInt(val, 10)
          port = isFinite(p) && p > 0 ? p : 0
        } else if (key === "LLAMA_API_KEY") apiKey = val
      }
      configHost = host
      configPort = port
      configApiKey = apiKey
    } else {
      try {
        var obj = JSON.parse(body)
        configHost = String(obj["host"] || "127.0.0.1")
        var p = parseInt(obj["port"], 10)
        configPort = isFinite(p) && p > 0 ? p : 0
        configApiKey = String(obj["api-key"] || "")
      } catch(e) {
        configHost = "127.0.0.1"
        configPort = 0
        configApiKey = ""
      }
    }
  }

  // Read-only startup probe: reports whether the config file exists (HAS/NO)
  // as the first output line and, if so, the file contents after it. Never
  // creates or modifies the file — creation is user-initiated via
  // createConfigFile().
  function ensureAndReadConfig() {
    launch(configProcess, configWatchdog)
  }

  function isCloudModel(name) {
    var n = String(name || "").toLowerCase()
    return n.indexOf(":cloud") !== -1 || n.indexOf(":server") !== -1
  }

  // ── Processes ──────────────────────────────────────────────────────
  //
  // Every command is wrapped in `timeout -k 2 N` which runs the command
  // in its own process group and kills the entire group on expiry,
  // preventing orphaned children.  Inside timeout, commands are further
  // wrapped in `bash -c "set -o pipefail; CMD 2>&1 | head -c N"` to bound
  // output at the OS pipe level before SplitParser sees it.
  //
  // With pipefail, SIGPIPE from head truncation yields exit 141.
  // timeout expiry yields exit 124 (TERM) or 137 (KILL).
  // All non-zero exits are discarded by the exitCode === 0 guard.

  Process {
    id: whichProcess
    running: false
    // which has no children and no stdout handler — timeout not needed
    command: ["which", root.backendBinary]
    onExited: function(exitCode) {
      whichWatchdog.stop()
      installed = exitCode === 0
      if (installed) refresh()
      else {
        hasService = false
        running = false
        models = []
        runningModels = []
        apiReachable = false
      }
    }
  }

  Process {
    id: checkServiceProcess
    running: false
    command: ["timeout", "-k", "2", "" + processTimeoutSec,
              "bash", "-c", "set -o pipefail; systemctl" + (root.backend === "llama.cpp" ? " --user" : "") + " list-unit-files " + root.backendService + " --no-legend 2>&1 | head -c " + root.capCheck]
    stdout: SplitParser { onRead: function(line) { root._onCheckLine(line) } }
    onExited: function(exitCode) {
      checkServiceWatchdog.stop()
      if (exitCode === 0) _parseCheckBuffer()
      else { _checkBuffer = ""; hasService = false }
    }
  }

  Process {
    id: serviceProcess
    running: false
    command: ["timeout", "-k", "2", "" + processTimeoutSec,
              "bash", "-c", "set -o pipefail; systemctl" + (root.backend === "llama.cpp" ? " --user" : "") + " show " + root.backendService.replace('.service', '') + " --property=ActiveState,SubState,ActiveEnterTimestamp 2>&1 | head -c " + root.capService]
    stdout: SplitParser { onRead: function(line) { root._onServiceLine(line) } }
    onExited: function(exitCode) {
      serviceWatchdog.stop()
      if (exitCode === 0) {
        _parseServiceBuffer()
      } else {
        _serviceBuffer = ""
        running = false
        activeSince = ""
        apiReachable = false
      }
    }
  }

  Process {
    id: apiHealthProcess
    running: false
    command: ["timeout", "-k", "2", "" + processTimeoutSec,
              "bash", "-c", "set -o pipefail; start=$(date +%s%3N); status=$(curl -s -o /dev/null -w '%{http_code}'" + root.apiKeyCurlHeader + " --connect-timeout 3 --max-time 5 " + root.effectiveHealthEndpoint + "); end=$(date +%s%3N); echo \"$status $((end - start))\" | head -c " + root.capApi]
    stdout: SplitParser { onRead: function(line) { root._onApiLine(line) } }
    onExited: function(exitCode) {
      apiHealthWatchdog.stop()
      if (exitCode === 0) {
        _parseApiBuffer()
      } else {
        _apiBuffer = ""
        apiReachable = false
        apiLatencyMs = -1
      }
    }
  }

  Process {
    id: listProcess
    running: false
    command: ["timeout", "-k", "2", "" + processTimeoutSec,
              "bash", "-c", "set -o pipefail; if [ \"" + root.backend + "\" = \"llama.cpp\" ]; then curl -s" + root.apiKeyCurlHeader + " http://" + root.effectiveHost + ":" + root.effectivePort + "/v1/models 2>&1 | head -c " + root.capList + "; else ollama list 2>&1 | head -c " + root.capList + "; fi"]
    stdout: SplitParser { onRead: function(line) { root.backend === "llama.cpp" ? root._onJsonLine(line) : root._onListLine(line) } }
    onExited: function(exitCode) {
      listWatchdog.stop()
      if (exitCode === 0) {
        if (root.backend === "llama.cpp") _finishJsonModels()
        else _finishList()
      } else {
        _listModels = []; _listHeaderSeen = false
        if (root.backend === "llama.cpp") runningModels = []
      }
    }
  }

  Process {
    id: psProcess
    running: false
    command: ["timeout", "-k", "2", "" + processTimeoutSec,
              "bash", "-c", "set -o pipefail; if [ \"" + root.backend + "\" = \"llama.cpp\" ]; then pgrep -af '[l]lama-server' | grep -oE '(--model|-m)[= ][^ ]+' 2>&1 | head -c " + root.capPs + "; else ollama ps 2>&1 | head -c " + root.capPs + "; fi"]
    stdout: SplitParser { onRead: function(line) { root.backend === "llama.cpp" ? root._onPgrepLine(line) : root._onPsLine(line) } }
    onExited: function(exitCode) {
      psWatchdog.stop()
      if (exitCode === 0) {
        if (root.backend === "llama.cpp") _finishPgrep()
        else _finishPs()
      } else {
        _psModels = []; _psHeaderSeen = false
      }
    }
  }

  Process {
    id: versionProcess
    running: false
    command: ["timeout", "-k", "2", "" + processTimeoutSec,
              "bash", "-c", "set -o pipefail; " + root.backendBinary + " --version 2>&1 | head -c " + root.capVersion]
    stdout: SplitParser { onRead: function(line) { root._onVersionLine(line) } }
    onExited: function(exitCode) {
      versionWatchdog.stop()
    }
  }

  // Config file: read-only probe. Emits a single HAS/NO marker line before
  // the file contents, so hasConfig is set even when the JSON is unparseable.
  // The pipeline runs without pipefail so `head -c` always exits 0 — a config
  // larger than capConfig truncates instead of being discarded.
  Process {
    id: configProcess
    running: false
    command: ["timeout", "-k", "2", "" + processTimeoutSec,
              "bash", "-c", "f='" + root.configPath + "'; { if [ -f \"$f\" ]; then echo HAS; cat \"$f\"; else echo NO; fi; } 2>/dev/null | head -c " + root.capConfig]
    stdout: SplitParser { onRead: function(line) { root._onConfigLine(line) } }
    onExited: function(exitCode) {
      configWatchdog.stop()
      _parseConfigBuffer()
    }
  }

  // llama.cpp user service → current DRAM working set (bytes). Sums anon+shmem
  // from the service cgroup's memory.stat: committed, non-reclaimable process
  // memory. MemoryCurrent is avoided because it also counts reclaimable
  // file/page cache (the mmap'd GGUF), which inflates the footprint and
  // double-counts weight pages already held as anon or on the GPU.
  Process {
    id: serviceMemoryProcess
    running: false
    command: ["timeout", "-k", "2", "" + processTimeoutSec,
              "bash", "-c",
              "cg=$(systemctl --user show " + root.backendService.replace('.service', '') + " --property=ControlGroup --value 2>/dev/null); " +
              "out=\"\"; " +
              "[ -n \"$cg\" ] && [ -r \"/sys/fs/cgroup$cg/memory.stat\" ] && out=$(awk '$1==\"anon\"{a=$2}$1==\"shmem\"{s=$2}END{print (a+0)+(s+0)}' \"/sys/fs/cgroup$cg/memory.stat\" 2>/dev/null); " +
              "[ -z \"$out\" ] && out=$(systemctl --user show " + root.backendService.replace('.service', '') + " --property=MemoryCurrent --value 2>/dev/null); " +
              "[ -n \"$out\" ] || out=0; " +
              "echo \"$out\" | head -c " + root.capServiceMemory]
    stdout: SplitParser { onRead: function(line) { root._onServiceMemoryLine(line) } }
    onExited: function(exitCode) {
      serviceMemoryWatchdog.stop()
      if (exitCode === 0) _finishServiceMemory()
      else { _serviceMemoryBuffer = ""; serviceMemoryBytes = -1; _deriveServiceTotal() }
    }
  }

  // llama.cpp user service → current per-service VRAM footprint (bytes).
  // Vendor auto-detected: nvidia-smi on NVIDIA, rocm-smi on AMD. The preset
  // server forks per-model workers that own the CUDA contexts, so GPU memory
  // is summed over every PID in the service cgroup (MainPID as fallback seed),
  // not just MainPID. When the model has no GPU context (idle/unloaded) or no
  // supported GPU tool exists, the query emits nothing and serviceVramBytes
  // stays -1 → CPU-only/unknown fallback.
  Process {
    id: serviceVramProcess
    running: false
    command: ["timeout", "-k", "2", "" + processTimeoutSec,
              "bash", "-c",
              "cg=$(systemctl --user show " + root.backendService.replace('.service', '') + " --property=ControlGroup --value 2>/dev/null); " +
              "pid=$(systemctl --user show " + root.backendService.replace('.service', '') + " --property=MainPID --value); " +
              "pids=\"$pid\"; [ -n \"$cg\" ] && [ -r \"/sys/fs/cgroup$cg/cgroup.procs\" ] && pids=\"$(tr '\\n' ' ' < \"/sys/fs/cgroup$cg/cgroup.procs\") $pid\"; " +
              "if command -v nvidia-smi >/dev/null 2>&1; then " +
              "nvidia-smi --query-compute-apps=pid,used_memory --format=csv,noheader,nounits 2>/dev/null | " +
              "awk -F',' -v ps=\"$pids\" 'BEGIN{n=split(ps,a,\" \");for(i=1;i<=n;i++)if(a[i]!=\"\")seen[a[i]]=1}{gsub(/[ \\t]/,\"\",$1);gsub(/[ \\t]/,\"\",$2);if(($1 in seen)&&$2~/^[0-9]+$/){sum+=$2;c++}}END{if(c>0)print sum\" MiB\"}'; " +
              "elif command -v rocm-smi >/dev/null 2>&1; then " +
              "rocm-smi --showmeminfo vram 2>/dev/null | head -2; " +
              "fi | head -c " + root.capServiceVram]
    stdout: SplitParser { onRead: function(line) { root._onServiceVramLine(line) } }
    onExited: function(exitCode) {
      serviceVramWatchdog.stop()
      if (exitCode === 0) _finishServiceVram()
      else { _serviceVramBuffer = ""; serviceVramBytes = -1; _deriveServiceTotal() }
    }
  }

  // ── Start/stop/create stderr capture ──────────────────────────────
  property string _startBuffer: ""
  property string _stopBuffer: ""
  property string _createBuffer: ""

  function _onStartLine(line) {
    var s = String(line || "")
    if (_startBuffer.length + s.length + 1 <= capAction) _startBuffer += s + "\n"
  }

  function _onStopLine(line) {
    var s = String(line || "")
    if (_stopBuffer.length + s.length + 1 <= capAction) _stopBuffer += s + "\n"
  }

  function _onCreateLine(line) {
    var s = String(line || "")
    if (_createBuffer.length + s.length + 1 <= capAction) _createBuffer += s + "\n"
  }

  Process {
    id: startProcess
    running: false
    command: {
      var script
      if (root.backend === "llama.cpp") {
        // Self-provision: env file + user unit, then start. One bash -c so
        // stderr is captured; set -e fail-fast; pipefail + head preserve the
        // real exit code into _startBuffer -> _actionError.
        script = "set -o pipefail; { set -e; d=$(dirname \"" + root.configPath + "\"); " +
          "ud=\"${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user\"; mkdir -p \"$d\" \"$ud\"; f=\"" + root.configPath + "\"; " +
          "if [ ! -f \"$f\" ]; then cat > \"$f\" <<ENV\n" + root.llamaEnvDefault + "ENV\nfi; " +
          "bin=$(command -v " + root.backendBinary + "); " +
          "cat > \"$ud/llama.cpp.service\" <<UNIT\n" +
          "[Unit]\nDescription=llama.cpp server (managed by local-ai-dashboard)\nAfter=network.target\n\n" +
          "[Service]\nType=simple\nEnvironmentFile=$f\n" +
          "ExecStart=/bin/bash -c 'exec \"$bin\" --host \"\\${LLAMA_HOST:-127.0.0.1}\" --port \"\\${LLAMA_PORT:-8080}\" " +
          "--models-preset \"\\${LLAMA_MODELS_PRESET}\" --models-max \"\\${LLAMA_MODELS_MAX:-1}\" \\${LLAMA_EXTRA_ARGS}'\n" +
          "Restart=on-failure\n\n[Install]\nWantedBy=default.target\nUNIT\n" +
          "systemctl --user daemon-reload; systemctl --user start llama.cpp.service; } 2>&1 | head -c " + root.capAction
      } else {
        script = "set -o pipefail; pkexec /usr/bin/systemctl start " + root.backendService + " 2>&1 | head -c " + root.capAction
      }
      return ["timeout", "-k", "2", "" + root.startTimeoutSec, "bash", "-c", script]
    }
    stdout: SplitParser { onRead: function(line) { root._onStartLine(line) } }
    onExited: function(exitCode) {
      startActionWatchdog.stop()
      busy = false
      actionLabel = ""
      if (exitCode !== 0) lastError = _actionError(_startBuffer, "start")
      else {
        lastError = ""
        if (root.backend === "llama.cpp") {
          hasConfig = true
          launch(configProcess, configWatchdog)
        }
      }
      _startBuffer = ""
      startDelay.restart()
    }
  }

  Process {
    id: stopProcess
    running: false
    command: ["timeout", "-k", "2", "" + processTimeoutSec,
              "bash", "-c", root.backend === "llama.cpp"
                ? "set -o pipefail; systemctl --user stop llama.cpp.service 2>&1 | head -c " + root.capAction
                : "set -o pipefail; pkexec /usr/bin/systemctl stop " + root.backendService + " 2>&1 | head -c " + root.capAction]
    stdout: SplitParser { onRead: function(line) { root._onStopLine(line) } }
    onExited: function(exitCode) {
      stopActionWatchdog.stop()
      busy = false
      actionLabel = ""
      if (exitCode !== 0) lastError = _actionError(_stopBuffer, "stop")
      else lastError = ""
      _stopBuffer = ""
      refresh()
    }
  }

  // Default config file creation. llama.cpp: plain bash, no pkexec — mkdir -p
  // the config dir then write the env template only if missing. ollama keeps
  // its single password prompt that writes the default JSON (stderr captured
  // and classified by _actionError just like start/stop).
  Process {
    id: createConfigProcess
    running: false
    command: ["timeout", "-k", "2", "" + startTimeoutSec,
              "bash", "-c", root.backend === "llama.cpp"
                ? "set -o pipefail; f='" + root.configPath + "'; { mkdir -p \"$(dirname \"$f\")\"; if [ ! -f \"$f\" ]; then cat > \"$f\" <<ENV\n" + root.llamaEnvDefault + "ENV\nfi; } 2>&1 | head -c " + root.capAction
                : "set -o pipefail; f='" + root.configPath + "'; pkexec /usr/bin/bash -c 'mkdir -p \"$(dirname \"$1\")\" && printf \"%s\" \"$2\" > \"$1\"' bash \"$f\" '" + root.defaultConfigJson + "' 2>&1 | head -c " + root.capAction]
    stdout: SplitParser { onRead: function(line) { root._onCreateLine(line) } }
    onExited: function(exitCode) {
      createConfigWatchdog.stop()
      busy = false
      actionLabel = ""
      if (exitCode !== 0) {
        lastError = _actionError(_createBuffer, "create")
      } else {
        lastError = ""
        hasConfig = true
        launch(configProcess, configWatchdog)
      }
      _createBuffer = ""
    }
  }

  // ── Watchdog timers (backup layer) ────────────────────────────────
  // These fire slightly after the `timeout` deadline so timeout (which
  // handles the process group) is the primary killer.  If timeout
  // itself hangs, the watchdog falls back to QProcess::terminate().

  Timer {
    id: whichWatchdog
    interval: watchdogMs
    repeat: false
    onTriggered: if (whichProcess.running) whichProcess.running = false
  }

  Timer {
    id: checkServiceWatchdog
    interval: watchdogMs
    repeat: false
    onTriggered: reap(checkServiceProcess, checkServiceWatchdog)
  }

  Timer {
    id: serviceWatchdog
    interval: watchdogMs
    repeat: false
    onTriggered: reap(serviceProcess, serviceWatchdog)
  }

  Timer {
    id: apiHealthWatchdog
    interval: watchdogMs
    repeat: false
    onTriggered: reap(apiHealthProcess, apiHealthWatchdog)
  }

  Timer {
    id: listWatchdog
    interval: watchdogMs
    repeat: false
    onTriggered: reap(listProcess, listWatchdog)
  }

  Timer {
    id: psWatchdog
    interval: watchdogMs
    repeat: false
    onTriggered: reap(psProcess, psWatchdog)
  }

  Timer {
    id: versionWatchdog
    interval: watchdogMs
    repeat: false
    onTriggered: reap(versionProcess, versionWatchdog)
  }

  Timer {
    id: configWatchdog
    interval: watchdogMs
    repeat: false
    onTriggered: reap(configProcess, configWatchdog)
  }

  Timer {
    id: serviceMemoryWatchdog
    interval: watchdogMs
    repeat: false
    onTriggered: reap(serviceMemoryProcess, serviceMemoryWatchdog)
  }

  Timer {
    id: serviceVramWatchdog
    interval: watchdogMs
    repeat: false
    onTriggered: reap(serviceVramProcess, serviceVramWatchdog)
  }

  Timer {
    id: startActionWatchdog
    interval: startWatchdogMs
    repeat: false
    onTriggered: if (startProcess.running) startProcess.running = false
  }

  Timer {
    id: stopActionWatchdog
    interval: watchdogMs
    repeat: false
    onTriggered: if (stopProcess.running) stopProcess.running = false
  }

  Timer {
    id: createConfigWatchdog
    interval: startWatchdogMs
    repeat: false
    onTriggered: if (createConfigProcess.running) createConfigProcess.running = false
  }

  // ── Refresh timers ─────────────────────────────────────────────────

  Timer {
    id: refreshTimer
    interval: refreshIntervalSec * 1000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: refresh()
  }

  Timer {
    id: startDelay
    interval: 1500
    repeat: false
    onTriggered: refresh()
  }

  Component.onCompleted: {
    whichProcess.running = true
    whichWatchdog.restart()
    ensureAndReadConfig()
  }
}
