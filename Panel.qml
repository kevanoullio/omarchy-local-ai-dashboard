import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "com.github.linuxgameruk.ollama-status"
  ipcTarget: "com.github.linuxgameruk.ollama-status"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // ── Active backend selection ────────────────────────────────────────
  property string activeBackend: "llama.cpp"
  readonly property var activeService: activeBackend === "llama.cpp" ? serviceLlama : serviceOllama

  // Exposed for the bar widget to read without its own Service instance.
  property var ollamaService: serviceOllama
  property var llamaService: serviceLlama

  function serviceStatus(svc) {
    if (svc.busy) return svc.actionLabel
    if (!svc.installed) return "Not installed"
    if (!svc.hasService) {
      if (svc.selfManaged) return "Configured"
      return "No service"
    }
    return svc.running ? "Running" : "Stopped"
  }

  function serviceStatusColor(svc) {
    if (svc.busy) return foreground
    if (!svc.installed) return urgent
    if (!svc.hasService) return svc.selfManaged ? foreground : urgent
    if (svc.running) return Color.accent
    return foreground
  }

  function switchBackend(name) {
    if (name !== "ollama" && name !== "llama.cpp") return
    if (name === activeBackend) return
    activeBackend = name
    if (hostWidget && typeof hostWidget.setActiveBackend === "function") {
      hostWidget.setActiveBackend(name)
    }
  }

  // Open the active backend's config file in the user's editor/terminal.
  function openConfig() {
    Util.execArgv(["omarchy", "launch", "config", "editor", root.activeService.configPath])
  }

  readonly property string statusText: serviceStatus(activeService)
  readonly property color statusColor: serviceStatusColor(activeService)
  readonly property string toggleHint: {
    var s = activeService
    if (!s.installed) return ""
    if (!s.hasService) {
      if (s.selfManaged) return "Ready \u2014 start creates config & service"
      return "See setup instructions below"
    }
    if (s.running) return "Turn " + s.backendDisplayName + " off"
    return "Turn " + s.backendDisplayName + " on"
  }

  property string focusSection: "header"
  property bool cursorActive: false

  function switchPanel(direction) {
    if (bar && typeof bar.switchPanelFrom === "function")
      return bar.switchPanelFrom(root.hostWidget || root, direction)
    return false
  }

  onOpenedChanged: if (opened) {
    cursorActive = false
    serviceOllama.refresh()
    serviceLlama.refresh()
    Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
  }

  Service {
    id: serviceOllama
    settings: root.settings
    backend: "ollama"
  }

  Service {
    id: serviceLlama
    settings: root.settings
    backend: "llama.cpp"
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function startService(): string { root.activeService.startService(); return "ok" }
    function stopService(): string { root.activeService.stopService(); return "ok" }
    function refresh(): string { root.serviceOllama.refresh(); root.serviceLlama.refresh(); return "ok" }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) root.cursorActive = true
      }
      onActivateRequested: {
        if (root.cursorActive && root.focusSection === "header") root.activeService.toggleService()
      }
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "s" || t === "S") root.activeService.startService()
        else if (t === "x" || t === "X") root.activeService.stopService()
        else if (t === "r" || t === "R") { root.serviceOllama.refresh(); root.serviceLlama.refresh() }
      }
    }

    Flickable {
      id: panelFlick
      anchors.fill: parent
      contentWidth: width
      contentHeight: column.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      flickableDirection: Flickable.VerticalFlick
      interactive: contentHeight > height
      ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

      Column {
        id: column
        width: panelFlick.width
        spacing: Style.space(12)

        // ── Hero: two backend cards + power switch ──────────────────
        Item {
          width: parent.width
          implicitHeight: heroRow.implicitHeight

          RowLayout {
            id: heroRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: Style.space(2)
            anchors.rightMargin: Style.space(6)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(8)

            BackendCard {
              Layout.fillWidth: true
              Layout.preferredWidth: Style.space(150)
              Layout.minimumWidth: Style.space(110)
              name: "llama.cpp"
              statusText: root.serviceStatus(root.serviceLlama)
              statusColor: root.serviceStatusColor(root.serviceLlama)
              active: root.activeBackend === "llama.cpp"
              onClicked: root.switchBackend("llama.cpp")
              onHovered: function(on) { if (on) { root.cursorActive = true; root.focusSection = "header" } }
            }

            BackendCard {
              Layout.fillWidth: true
              Layout.preferredWidth: Style.space(150)
              Layout.minimumWidth: Style.space(110)
              name: "ollama"
              statusText: root.serviceStatus(root.serviceOllama)
              statusColor: root.serviceStatusColor(root.serviceOllama)
              active: root.activeBackend === "ollama"
              onClicked: root.switchBackend("ollama")
              onHovered: function(on) { if (on) { root.cursorActive = true; root.focusSection = "header" } }
            }

            ToggleSwitch {
              id: powerSwitch
              Layout.alignment: Qt.AlignVCenter
              Layout.fillWidth: false
              Layout.minimumWidth: implicitWidth
              visible: root.activeService.installed && (root.activeService.hasService || root.activeService.selfManaged)
              checked: root.activeService.running
              busy: root.activeService.busy
              enabled: root.activeService.selfManaged || root.activeService.hasConfig
              opacity: (root.activeService.selfManaged || root.activeService.hasConfig) ? 1.0 : 0.5
              hasCursor: root.cursorActive && root.focusSection === "header"
              foreground: root.foreground
              onHovered: function(on) { if (on) { root.cursorActive = true; root.focusSection = "header" } }
              onToggled: root.activeService.toggleService()

              PanelToolTip {
                visible: powerSwitch.containsMouse
                text: root.toggleHint
                fontFamily: root.fontFamily
              }
            }
          }
        }

        // ── Error ───────────────────────────────────────────────────
        Text {
          visible: root.activeService.lastError !== ""
          width: parent.width
          text: root.activeService.sanitize(root.activeService.lastError)
          color: root.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
        }

        // ── Not installed ────────────────────────────────────────────
        CursorSurface {
          visible: !root.activeService.installed
          width: parent.width
          implicitHeight: missingText.implicitHeight + Style.spacing.rowPaddingX
          foreground: root.foreground

          Text {
            id: missingText
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: Style.space(12)
            text: root.activeService.backendDisplayName + " is not installed or not on PATH.\nInstall it and try again."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
          }
        }

        // ── No service ────────────────────────────────────────────────
        CursorSurface {
          visible: root.activeService.installed && !root.activeService.hasService && !root.activeService.selfManaged
          width: parent.width
          implicitHeight: noServiceText.implicitHeight + Style.spacing.rowPaddingX
          foreground: root.foreground

          Text {
            id: noServiceText
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: Style.space(12)
            text: root.activeService.backendDisplayName + " is installed but has no systemd service.\nSet one up with:\n\nsudo systemctl enable " + root.activeService.backendService.replace('.service', '') + "\n\nSee the README for a unit file if none is packaged."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
          }
        }

        // ── Service details ─────────────────────────────────────────
        Column {
          visible: root.activeService.installed && (root.activeService.hasService || root.activeService.selfManaged)
          width: parent.width
          spacing: Style.spacing.labelGap

          GridLayout {
            width: parent.width
            columns: 2
            columnSpacing: Style.space(20)
            rowSpacing: Style.spacing.labelGap

            InfoLabel { text: "Status" }
            InfoValue {
              text: root.activeService.running ? "Running" : "Stopped"
              color: root.statusColor
            }

            InfoLabel { text: "Version" }
            InfoValue {
              text: root.activeService.sanitize(root.activeService.ollamaVersion) || "\u2014"
            }

            InfoLabel {
              visible: root.activeService.running
              text: "API"
            }
            InfoValue {
              visible: root.activeService.running
              text: root.activeService.apiReachable ? root.activeService.effectiveHost + ":" + root.activeService.effectivePort : "\u2014"
              color: !root.activeService.apiReachable ? root.urgent : root.foreground
            }

            InfoLabel {
              visible: root.activeService.running && root.activeService.apiReachable
              text: "Latency"
            }
            InfoValue {
              visible: root.activeService.running && root.activeService.apiReachable
              text: root.activeService.apiLatencyMs >= 0 ? root.activeService.apiLatencyMs + " ms" : "\u2014"
              color: {
                if (root.activeService.apiLatencyMs > 500) return root.urgent
                if (root.activeService.apiLatencyMs > 200) return Color.accent
                return root.foreground
              }
            }

            InfoLabel {
              visible: root.activeService.running && root.activeService.activeSince !== ""
              text: "Since"
            }
            InfoValue {
              visible: root.activeService.running && root.activeService.activeSince !== ""
              text: root.activeService.activeSince ? root.activeService.sanitize(root.activeService.activeSince.replace(/^\w+\s+/, "")) : ""
            }

            SettingsButton {
              Layout.columnSpan: 2
              Layout.fillWidth: true
              label: "Configure " + root.activeService.backendDisplayName
              enabled: root.activeService.hasConfig
              onClicked: root.openConfig()
            }

            SettingsButton {
              Layout.columnSpan: 2
              Layout.fillWidth: true
              visible: !root.activeService.hasConfig
              label: "Create " + root.activeService.backendDisplayName + " config file"
              onClicked: root.activeService.createConfigFile()
            }

          }
        }

        // ── Running models ──────────────────────────────────────────
        PanelSeparator {
          visible: root.activeService.running && root.activeService.runningModels.length > 0
          foreground: root.foreground
        }

        Column {
          visible: root.activeService.running && root.activeService.runningModels.length > 0
          width: parent.width
          spacing: Style.space(10)

          PanelSectionHeader {
            text: "LOADED MODELS"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Column {
            width: parent.width
            spacing: Style.space(6)

            Repeater {
              model: root.activeService.runningModels

              CursorSurface {
                required property var modelData
                width: parent.width
                foreground: root.foreground
                implicitHeight: modelRow.implicitHeight + Style.spacing.rowPaddingX

                RowLayout {
                  id: modelRow
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.leftMargin: Style.space(10)
                  anchors.rightMargin: Style.space(10)
                  spacing: Style.space(8)

                  Text {
                    text: "󰚩"
                    color: Color.accent
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    textFormat: Text.PlainText
                    Layout.alignment: Qt.AlignVCenter
                  }

                  ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Style.space(1)

                    Text {
                      Layout.fillWidth: true
                      text: root.activeService.sanitize(modelData.name || "Unknown")
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      textFormat: Text.PlainText
                      elide: Text.ElideRight
                    }

                    Text {
                      Layout.fillWidth: true
                      text: {
                        var parts = []
                        if (modelData.size) parts.push(String(modelData.size))
                        if (modelData.processor) parts.push(String(modelData.processor))
                        return root.activeService.sanitize(parts.join(" \u00b7 "))
                      }
                      visible: text !== ""
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      textFormat: Text.PlainText
                      elide: Text.ElideRight
                    }
                  }
                }
              }
            }
          }
        }

        // ── Available models ─────────────────────────────────────────
        PanelSeparator {
          visible: root.activeService.installed && root.activeService.models.length > 0
          foreground: root.foreground
        }

        Column {
          visible: root.activeService.installed && root.activeService.models.length > 0
          width: parent.width
          spacing: Style.space(10)

          PanelSectionHeader {
            text: {
              var local = 0
              var cloud = 0
              for (var i = 0; i < root.activeService.models.length; i++) {
                if (root.activeService.models[i].isCloud) cloud++
                else local++
              }
              var parts = []
              if (local > 0) parts.push(local + " local")
              if (cloud > 0) parts.push(cloud + " cloud")
              var count = parts.length > 0 ? "  " + parts.join(" \u00b7 ") : ""
              return (root.activeService.running ? "ALL MODELS" : "AVAILABLE MODELS") + count
            }
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Column {
            width: parent.width
            spacing: Style.space(6)

            Repeater {
              model: root.activeService.models

              CursorSurface {
                required property var modelData
                width: parent.width
                foreground: root.foreground
                implicitHeight: availRow.implicitHeight + Style.spacing.rowPaddingX

                RowLayout {
                  id: availRow
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.leftMargin: Style.space(10)
                  anchors.rightMargin: Style.space(10)
                  spacing: Style.space(8)

                  Text {
                    text: {
                      if (modelData.isCloud) return "\u2601"
                      for (var i = 0; i < root.activeService.runningModels.length; i++) {
                        if (String(root.activeService.runningModels[i].name) === String(modelData.name)) return "\u25cf"
                      }
                      return "\u25cb"
                    }
                    color: {
                      if (modelData.isCloud) return Color.accent
                      for (var i = 0; i < root.activeService.runningModels.length; i++) {
                        if (String(root.activeService.runningModels[i].name) === String(modelData.name)) return Color.accent
                      }
                      return root.dim
                    }
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    textFormat: Text.PlainText
                    Layout.alignment: Qt.AlignVCenter
                  }

                  ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Style.space(1)

                    Text {
                      Layout.fillWidth: true
                      text: root.activeService.sanitize(modelData.name || "Unknown")
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      textFormat: Text.PlainText
                      elide: Text.ElideRight
                    }

                    Text {
                      Layout.fillWidth: true
                      text: {
                        var parts = []
                        if (modelData.isCloud) parts.push("Cloud")
                        else if (modelData.size) parts.push(String(modelData.size))
                        if (modelData.modified) parts.push(String(modelData.modified))
                        return root.activeService.sanitize(parts.join(" \u00b7 "))
                      }
                      visible: text !== ""
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      textFormat: Text.PlainText
                      elide: Text.ElideRight
                    }
                  }
                }
              }
            }
          }
        }

        // ── No models loaded ─────────────────────────────────────────
        PanelSeparator {
          visible: root.activeService.running && root.activeService.runningModels.length === 0
          foreground: root.foreground
        }

        Text {
          visible: root.activeService.running && root.activeService.runningModels.length === 0
          width: parent.width
          text: root.activeService.models.length === 0 ? "No local models. Cloud models accessed via API are not listed by " + root.activeService.backendDisplayName + "." : "No models currently loaded. Service is idle."
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          horizontalAlignment: Text.AlignHCenter
        }
      }
    }
  }

  // ── Inline components matching Omarchy panel style ──────────────────

  component InfoLabel: Text {
    color: root.foreground
    opacity: 0.6
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    textFormat: Text.PlainText
  }

  component InfoValue: Text {
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    textFormat: Text.PlainText
  }

  // A clickable backend selector: name + live status below, like the
  // original hero. The active card is highlighted.
  component BackendCard: Item {
    required property string name
    required property string statusText
    required property color statusColor
    required property bool active
    signal clicked()
    signal hovered(bool on)

    property bool _hover: false

    implicitWidth: Math.max(nameLabel.implicitWidth, statusLabel.implicitWidth) + Style.space(24)
    implicitHeight: contentCol.implicitHeight + Style.space(14)

    Rectangle {
      anchors.fill: parent
      radius: Style.space(6)
      color: {
        if (root.cursorActive && root.focusSection === "header" && parent._hover)
          return Style.hoverBorderFor(root.foreground, Color.accent)
        if (parent.active)
          return Style.selectedFillFor(root.foreground, Color.accent)
        return Style.normalBorderFor(root.foreground, Color.accent)
      }
      border.color: parent.active ? root.foreground : Qt.darker(root.foreground, 1.7)
      border.width: 1
    }

    Row {
      id: contentCol
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(6)

      Text {
        text: "󰚩"
        color: statusColor
        font.family: root.fontFamily
        font.pixelSize: Style.font.title
        textFormat: Text.PlainText
        verticalAlignment: Text.AlignVCenter
      }

      Column {
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(1)

        Text {
          id: nameLabel
          text: name
          color: statusColor
          font.family: root.fontFamily
          font.pixelSize: Style.font.title
          font.bold: true
          textFormat: Text.PlainText
          elide: Text.ElideRight
        }

        Text {
          id: statusLabel
          text: statusText.toUpperCase()
          color: statusColor
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
          font.letterSpacing: 1.2
          textFormat: Text.PlainText
          elide: Text.ElideRight
        }
      }
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: { parent._hover = true; parent.hovered(true) }
      onExited: { parent._hover = false; parent.hovered(false) }
      onClicked: parent.clicked()
    }
  }

  // A simple full-width button that opens the backend's config file in the
  // user's editor/terminal (via `omarchy launch config editor`). `enabled`
  // dims the button and ignores clicks.
  component SettingsButton: Item {
    id: sb
    required property string label
    property bool enabled: true
    signal clicked()

    property bool _hover: false

    implicitHeight: contentRow.implicitHeight + Style.space(10)

    Rectangle {
      anchors.fill: parent
      radius: Style.space(4)
      color: (sb.enabled && sb._hover)
        ? Style.hoverBorderFor(root.foreground, Color.accent)
        : Style.normalBorderFor(root.foreground, Color.accent)
      border.color: Qt.darker(root.foreground, 1.7)
      border.width: 1
      opacity: sb.enabled ? 1.0 : 0.5
    }

    Text {
      id: contentRow
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(12)
      anchors.rightMargin: Style.space(12)
      text: sb.label
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      textFormat: Text.PlainText
      horizontalAlignment: Text.AlignHCenter
      elide: Text.ElideRight
      opacity: sb.enabled ? 1.0 : 0.5
    }

    MouseArea {
      anchors.fill: parent
      enabled: sb.enabled
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: sb._hover = true
      onExited: sb._hover = false
      onClicked: sb.clicked()
    }
  }
}
