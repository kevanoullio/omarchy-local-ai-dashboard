import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

// Model inventory section: currently loaded models, the full available
// model list, and the "no models" empty state. Display-only — all data
// arrives via `service`, no signals are emitted.
Item {
  id: root

  required property var service
  required property color foreground
  required property color dim
  required property color urgent
  required property string fontFamily

  implicitHeight: contentCol.implicitHeight
  width: parent ? parent.width : 0

  // Render an ollama loaded-model detail line in the same format as
  // llama.cpp: "<size> | CPU: X% | GPU: Y%". Splits the already-provided
  // `modelData.processor` string (e.g. "100% CPU", "51%/49% CPU/GPU").
  // Returns "" when the string can't be parsed so callers can fall back.
  function ollamaDetailLine(modelData) {
    var proc = String(modelData && modelData.processor || "").trim()
    var sizeStr = modelData && modelData.size ? String(modelData.size) : ""
    var cpu = -1
    var gpu = -1
    var m = proc.match(/^(\d+)%\s*\/\s*(\d+)%\s*CPU\/GPU/)
    if (m) {
      cpu = parseInt(m[1], 10)
      gpu = parseInt(m[2], 10)
    } else {
      m = proc.match(/^(\d+)%\s*CPU/)
      if (m) {
        cpu = parseInt(m[1], 10)
        gpu = 100 - cpu
      } else {
        m = proc.match(/^(\d+)%\s*GPU/)
        if (m) {
          gpu = parseInt(m[1], 10)
          cpu = 100 - gpu
        }
      }
    }
    if (sizeStr === "" || cpu < 0 || gpu < 0) return ""
    var parts = []
    parts.push("Memory: " + sizeStr)
    parts.push("CPU: " + cpu + "%")
    parts.push("GPU: " + gpu + "%")
    return root.service.sanitize(parts.join(" | "))
  }

  Column {
    id: contentCol
    width: parent.width
    spacing: Style.space(10)

    // ── Running models ──────────────────────────────────────────
    PanelSeparator {
      visible: root.service.running && root.service.runningModels.length > 0
      foreground: root.foreground
    }

    Column {
      visible: root.service.running && root.service.runningModels.length > 0
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
          model: root.service.runningModels

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
                  text: root.service.sanitize(modelData.name || "Unknown")
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  textFormat: Text.PlainText
                  elide: Text.ElideRight
                }

                Text {
                  Layout.fillWidth: true
                  text: {
                    if (root.service.backend === "llama.cpp") {
                      var cpuPct = root.service.cpuSplitPercent()
                      if (cpuPct >= 0) {
                        return root.service.sanitize("Memory: " + root.service.memoryTotalGB() + " | CPU: " + cpuPct + "% | GPU: " + (100 - cpuPct) + "%")
                      }
                      return "Memory unavailable"
                    }
                    var ollamaLine = root.ollamaDetailLine(modelData)
                    if (ollamaLine !== "") return ollamaLine
                    return "Memory unavailable"
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
      visible: root.service.installed && root.service.models.length > 0
      foreground: root.foreground
    }

    Column {
      visible: root.service.installed && root.service.models.length > 0
      width: parent.width
      spacing: Style.space(10)

      PanelSectionHeader {
        text: {
          var local = 0
          var cloud = 0
          for (var i = 0; i < root.service.models.length; i++) {
            if (root.service.models[i].isCloud) cloud++
            else local++
          }
          var parts = []
          if (local > 0) parts.push(local + " local")
          if (cloud > 0) parts.push(cloud + " cloud")
          var count = parts.length > 0 ? "  " + parts.join(" \u00b7 ") : ""
          return (root.service.running ? "ALL MODELS" : "AVAILABLE MODELS") + count
        }
        foreground: root.foreground
        fontFamily: root.fontFamily
      }

      Column {
        width: parent.width
        spacing: Style.space(6)

        Repeater {
          model: root.service.models

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
                  for (var i = 0; i < root.service.runningModels.length; i++) {
                    if (String(root.service.runningModels[i].name) === String(modelData.name)) return "\u25cf"
                  }
                  return "\u25cb"
                }
                color: {
                  if (modelData.isCloud) return Color.accent
                  for (var i = 0; i < root.service.runningModels.length; i++) {
                    if (String(root.service.runningModels[i].name) === String(modelData.name)) return Color.accent
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
                  text: root.service.sanitize(modelData.name || "Unknown")
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
                    else if (modelData.size) parts.push("Model size: " + String(modelData.size))
                    if (modelData.modified) parts.push("Downloaded: " + String(modelData.modified))
                    return root.service.sanitize(parts.join(" | "))
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
      visible: root.service.running && root.service.runningModels.length === 0
      foreground: root.foreground
    }

    Text {
      visible: root.service.running && root.service.runningModels.length === 0
      width: parent.width
      text: root.service.models.length === 0 ? "No local models. Cloud models accessed via API are not listed by " + root.service.backendDisplayName + "." : "No models currently loaded. Service is idle."
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      textFormat: Text.PlainText
      wrapMode: Text.WordWrap
      horizontalAlignment: Text.AlignHCenter
    }
  }
}
