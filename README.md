# omarchy-local-ai-dashboard
Monitor and control local ai model services like ollama/llama-server/vllm from the Omarchy bar. Start and stop the systemd background service, view available models with current model status, monitor CPU/GPU/DRAM/VRAM usage, with quick access to view debug output via a new terminal session, and one click open your config files via nvim.

It provides a unified interface for various local backends—including `Ollama`, `llama-server`, `llama-swap`, and `vLLM`, allowing you to inspect models, adjust service setups, stream terminal logs, and enforce single-service resource isolation.

This project is an extended derivative work based on `omarchy-ollama-status` by LinuxGamerUK.

---

## Plugin Identification

- **Plugin Name:** `local-ai-dashboard`
- **Full Identifier:** `kevano.local-ai-dashboard`
- **Target Platform:** Omarchy 4 (Quattro / Quickshell Engine)

---

## Features & Architecture

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
| Ollama       | llama-server | vLLM         |
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
Displays an itemized list of all local models recognized by the selected service engine (e.g., local GGUFs for `llama-server`, pulled models for `Ollama`).

#### Tab 3: Loaded Model
Provides real-time telemetry for the currently loaded model instance:

- **Model Name:** Currently active model identifier.
- **Resource Split:** Layer offload ratio between CPU RAM and GPU VRAM.
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

2. Register the plugin inside your Omarchy 4 configuration file (`~/.config/omarchy/shell.json`):
```json
{
  "bar": {
    "widgets": [
      "omarchy.menu",
      "omarchy.workspaces",
      "kevano.local-ai-dashboard",
      "omarchy.clock"
    ]
  }
}

```


3. Restart or reload your Omarchy shell session.

---

## Dependencies

The dashboard relies on standard Linux utilities to query local APIs and manage background units:

* `curl` and `jq` for API response handling.
* `systemd` user service manager (or process supervisor).
* `nvim` for inline file editing.
* Your preferred terminal emulator (e.g., `kitty`, `foot`) for log streaming.

---

## Credits & License

* **Original Inspiration:** Based on [`omarchy-ollama-status`](https://github.com/LinuxGamerUK/omarchy-ollama-status) by **LinuxGamerUK**.
* **License:** Distributed under the terms of the [MIT License](https://www.google.com/search?q=LICENSE).
