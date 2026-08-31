# omarchy-local-ai-dashboard
Monitor and control local AI model services like ollama and llama.cpp from the Omarchy bar. Start and stop systemd background services, view available models with current status, monitor CPU/GPU/DRAM/VRAM usage, stream debug output via a new terminal session, and open config files directly in nvim.

It provides a unified interface for various local backends—including `ollama`, `llama-server`, and `llama-swap`—allowing you to inspect models, adjust service setups, stream terminal logs, and enforce single-service resource isolation. Support for `vLLM` is a planned feature.

This project is an extended derivative work based on `omarchy-ollama-status` by LinuxGamerUK.

---

## Plugin Identification

- **Plugin Name:** `local-ai-dashboard`
- **Full Identifier:** `kevano.local-ai-dashboard`
- **Target Platform:** Omarchy 4 (Quattro / Quickshell Engine)

---

## Project Structure

The plugin is split into a `Dashboard.qml` shell that owns all shared state
(backend selection, cursor/keyboard navigation, `Service` instances) plus a set
of reusable UI components and per-section files. Each section is "state-in /
signal-out": it receives data as properties and reports interactions back as
signals, so the shell remains the single source of truth.

```
kevano.local-ai-dashboard/
├── assets/                          # Static assets (icons, etc.)
├── configs/                         # Per-backend configuration files
│   ├── llama.env                    #   llama.cpp env template / config
│   └── ollama.json                  #   ollama JSON config
├── sections/                        # Dashboard section components
│   ├── HeroSection.qml              #   Backend cards + power toggle
│   ├── ServiceDetailsSection.qml    #   Status/version/API grid + configure buttons
│   └── ModelsSection.qml            #   Running + available model lists
├── ui/                              # Reusable UI components
│   ├── BackendCard.qml              #   Clickable backend selector card
│   ├── InfoLabel.qml                #   Dimmed detail-row label
│   ├── InfoValue.qml                #   Detail-row value text
│   └── SettingsButton.qml           #   Full-width config action button
├── BarWidget.qml                    # Bar icon button (the plugin entry point)
├── Controller.qml                   # Loads and wires the dashboard panel
├── Dashboard.qml                    # The panel shell: structure + shared state
├── Service.qml                      # Backend service model (systemctl/API logic)
├── LICENSE
├── manifest.json                    # Plugin metadata + entry point declaration
└── README.md
```

`manifest.json` points the bar at `BarWidget.qml` (`entryPoints.barWidget`), which
registers a `Controller` that loads `Dashboard.qml` on demand. Both the
`Service.qml` model and the `qs.Ui` panel primitives (`Panel`,
`KeyboardPanel`, `CursorSurface`, etc.) are reused across the sections.

---

## Features & Architecture

- **Dual systemd scope model:** ollama runs as a system-wide daemon (system instance, managed via `pkexec`), while llama.cpp runs as a per-user service (user instance, self-provisioned on first start with no root or polkit required). Both can run side-by-side independently.
- **Multi-Service Selection Bar:** Displays all installed or configured local AI services at a glance. Easily switch the target view without affecting active background processes.
- **Single-Active Service Enforcer:** Activating a service automatically initiates a graceful shutdown of any currently running backend and waits for complete resource/VRAM forfeit before starting the target engine.
- **Tabbed Management Interface:** Organized sub-views for service control, model inventory, live context tracking, and runtime configuration.
- **Interactive Terminal Debugging:** One-click action to launch a terminal attached to live systemd or process logs.
- **Inline Neovim Configuration:** View service config file locations and open them directly in Neovim for editing.

---

## Interface Layout

### Header: Service Selector

The top header presents a horizontal row of available local services. Each service is represented by a single-column, two-row element:


```

+--------------+--------------+--------------+
| ollama       | llama-server | vLLM         |
| RUNNING      | STOPPED      | STOPPED      |
+--------------+--------------+--------------+

```

- **Selected View:** The currently selected service name is rendered in bold, bright text. Non-selected services are dimmed.
- **Interactive Selection:** Clicking any service column changes the active tab focus below to that service. Inspecting a service in this manner does not alter its running state.

---

### Lower Section: Tabbed Inspector & Manager

The lower section contains four dedicated tabs to manage and inspect the selected service.

#### Tab 1: Manage Service
Handles primary power management and operational health for the selected backend.

- **Service & Toggle:** Shows the service name alongside a prominent On/Off toggle switch.
- **Status:** Displays operational state (`RUNNING` or `STOPPED`).
- **Version:** Displays the binary or API version string reported by the engine.
- **Since:** Timestamp recording when the active service was started.

#### Tab 2: All Models
Displays an itemized list of all local models recognized by the selected service engine (e.g., local GGUFs for `llama-server`, pulled models for `ollama`).

#### Tab 3: Loaded Model
Provides real-time telemetry for the currently loaded model instance:

- **Model Name:** Currently active model identifier.
- **Memory (llama.cpp):** The actual full process footprint — measured DRAM
  working set (the service cgroup's `anon` + `shmem`, i.e. RAM-resident
  weights, context, compute, and mmproj) added to measured per-service VRAM
  (`nvidia-smi` on NVIDIA, `rocm-smi` on AMD). Reclaimable file/page cache
  (the mmap'd `.gguf`) is deliberately excluded so the number reflects
  committed memory rather than the cached model file. This is the true total
  memory used, exceeding the raw model file size once context/mmproj are
  allocated.
- **Resource Split:** Measured CPU (DRAM) / GPU (VRAM) share of that total:
  `CPU% = DRAM / (DRAM + VRAM)`, `GPU% = 100 - CPU%`.
- **Context Meter:** Visual representation of context memory allocated versus used (Context Size / Context Limit).

#### Tab 4: Setup
Provides direct access to runtime parameters, system files, and logging tools.

- **Debug Output:** Action button to spawn a terminal running live system logs (`journalctl` / `tmux attach`).
- **Configuration Files:** List of configuration files associated with the service, formatted as:
  `[File Path] -> [Edit in Neovim]`
- **Port:** Editable in-line field for the network port assignment.
- **API Key:** Editable in-line field for local authorization tokens (if configured).

---

## Installation & Setup

1. Clone this repository into your Omarchy plugins directory:

   ```bash
   git clone [https://github.com/YOUR_USERNAME/omarchy-local-ai-dashboard.git](https://github.com/YOUR_USERNAME/omarchy-local-ai-dashboard.git) ~/.config/omarchy/plugins/local-ai-dashboard

```

2. Register the plugin by adding it to a `bar.layout` region in your Omarchy 4 configuration file (`~/.config/omarchy/shell.json`). For example, the right region:
```json
{
  "bar": {
    "layout": {
      "right": [
        { "id": "kevano.local-ai-dashboard" }
      ]
    }
  }
}
```


3. Restart or reload your Omarchy shell session.

---

## Service Architecture

### ollama — system instance

ollama is installed as a system-wide daemon (`/usr/lib/systemd/system/ollama.service`) that runs under a dedicated `ollama` user, stores models in `/usr/share/ollama`, and serves on a static port. The dashboard manages it via the **system** systemd instance using `pkexec` (which triggers a graphical polkit authentication prompt).

### llama.cpp — user instance

llama.cpp is designed as a flexible, developer-focused binary. Users frequently change parameter flags, swap local model files, adjust VRAM layer offloading, and edit preset `.ini` files. This per-user workflow aligns naturally with **user-scoped** systemd services.

When you toggle llama.cpp on for the first time, the plugin self-provisions both its configuration file (`configs/llama.env`) and its user service unit (`~/.config/systemd/user/llama.cpp.service`) automatically — no root privileges or polkit authentication required.

### Side-by-side operation

The two services live in separate systemd scopes (system vs. user instance), so they can run simultaneously without conflict. The dashboard's single-active enforcer handles switching between them when needed.

---

## Dependencies

The dashboard relies on standard Linux utilities to query local APIs and manage background units:

* `curl` and `jq` for API response handling.
* `systemd` (both system and user service instances).
* A polkit authentication agent for managing ollama's system-level service via `pkexec` (Omarchy ships one by default).
* `nvim` for inline file editing.
* Your preferred terminal emulator (e.g., `kitty`, `foot`) for log streaming.

---

## Credits & License

* **Original Inspiration:** Based on [`omarchy-ollama-status`](https://github.com/LinuxGamerUK/omarchy-ollama-status) by **LinuxGamerUK**.
* **License:** Distributed under the terms of the [MIT License](https://www.google.com/search?q=LICENSE).
