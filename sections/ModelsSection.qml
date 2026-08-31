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
                    var parts = []
                    if (modelData.size) parts.push(String(modelData.size))
                    if (modelData.processor) parts.push(String(modelData.processor))
                    return root.service.sanitize(parts.join(" \u00b7 "))
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
                    else if (modelData.size) parts.push(String(modelData.size))
                    if (modelData.modified) parts.push(String(modelData.modified))
                    return root.service.sanitize(parts.join(" \u00b7 "))
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
