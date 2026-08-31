import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "../ui" as UI

// Hero section: two clickable backend cards + the active backend's power
// toggle. Emits `sectionHovered` so the dashboard can drive cursor
// navigation state; all data is passed in (state-in / signal-out).
Item {
  id: root

  required property string llamaStatusText
  required property color llamaStatusColor
  required property string ollamaStatusText
  required property color ollamaStatusColor
  required property string activeBackend

  // Active (selected) service object, used for the power toggle state.
  required property var activeService

  required property string toggleHint
  required property color foreground
  required property string fontFamily

  // True when the header is the keyboard-focus target (cursorActive &&
  // focusSection === "header" on the dashboard). Drives card/toggle highlight.
  property bool headerActive: false

  signal backendSelected(string name)
  signal toggleRequested()
  signal sectionHovered()

  implicitHeight: heroRow.implicitHeight

  RowLayout {
    id: heroRow
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.leftMargin: Style.space(2)
    anchors.rightMargin: Style.space(6)
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(8)

    UI.BackendCard {
      Layout.fillWidth: true
      Layout.preferredWidth: Style.space(150)
      Layout.minimumWidth: Style.space(110)
      label: "llama.cpp"
      statusText: root.llamaStatusText
      statusColor: root.llamaStatusColor
      foreground: root.foreground
      fontFamily: root.fontFamily
      active: root.activeBackend === "llama.cpp"
      highlighted: root.headerActive
      onClicked: root.backendSelected("llama.cpp")
      onHovered: function(on) { if (on) root.sectionHovered() }
    }

    UI.BackendCard {
      Layout.fillWidth: true
      Layout.preferredWidth: Style.space(150)
      Layout.minimumWidth: Style.space(110)
      label: "ollama"
      statusText: root.ollamaStatusText
      statusColor: root.ollamaStatusColor
      foreground: root.foreground
      fontFamily: root.fontFamily
      active: root.activeBackend === "ollama"
      highlighted: root.headerActive
      onClicked: root.backendSelected("ollama")
      onHovered: function(on) { if (on) root.sectionHovered() }
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
      hasCursor: root.headerActive
      foreground: root.foreground
      onHovered: function(on) { if (on) root.sectionHovered() }
      onToggled: root.toggleRequested()

      PanelToolTip {
        visible: powerSwitch.containsMouse
        text: root.toggleHint
        fontFamily: root.fontFamily
      }
    }
  }
}
