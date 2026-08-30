import QtQuick
import Quickshell
import qs.Ui
import qs.Commons

BarWidget {
  id: root
  moduleName: "kevano.local-ai-dashboard"

  readonly property bool opened: panelLoader.item
    ? panelLoader.item.opened === true
    : false
  readonly property bool popoutSwitchClosing: panelLoader.item
    ? panelLoader.item.popoutSwitchClosing === true
    : false

  property string activeBackend: "llama.cpp"

  function setActiveBackend(name) {
    if (name === "ollama" || name === "llama.cpp") activeBackend = name
  }

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function toggle() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  function injectPanel() {
    if (!panelLoader.item) return
    panelLoader.item.bar = root.bar
    panelLoader.item.anchorItem = button
    panelLoader.item.hostWidget = root
  }

  function serviceStateString(svc) {
    if (!svc) return "…"
    if (!svc.installed) return "Not installed"
    if (!svc.hasService) return "No service"
    return svc.running ? "Running" : "Stopped"
  }

  readonly property var _activeService: panelLoader.item
    ? (activeBackend === "llama.cpp" ? panelLoader.item.llamaService : panelLoader.item.ollamaService)
    : null

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()

  readonly property color barIconColor: {
    var s = _activeService
    var base = bar ? bar.barForeground : Color.foreground
    if (!s || !s.installed || !s.hasService) return Qt.darker(base, 2.0)
    if (s.running) return base
    return Qt.darker(base, 1.55)
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    tooltipText: {
      var p = panelLoader.item
      if (!p) return "Local AI"
      return "Llama.cpp \u00b7 " + root.serviceStateString(p.llamaService) +
             "   |   Ollama \u00b7 " + root.serviceStateString(p.ollamaService)
    }
    iconComponent: Component {
      Item {
        Text {
          anchors.centerIn: parent
          text: "󰚩"
          color: root.barIconColor
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.bar.iconFont
          renderType: Text.NativeRendering
          textFormat: Text.PlainText

          Behavior on color { ColorAnimation { duration: 240 } }
        }
      }
    }

    onPressed: function(buttonCode) {
      if (buttonCode === Qt.LeftButton) root.toggle()
      else {
        var s = root._activeService
        if (!s) return
        if (buttonCode === Qt.RightButton) s.toggleService()
        else if (buttonCode === Qt.MiddleButton) s.refresh()
      }
    }
  }
}