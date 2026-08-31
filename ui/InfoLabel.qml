import QtQuick
import qs.Commons

// A dimmed label used for service detail rows (Status, Version, API, ...).
Text {
  id: root
  required property color foreground
  required property string fontFamily

  color: foreground
  opacity: 0.6
  font.family: fontFamily
  font.pixelSize: Style.font.bodySmall
  textFormat: Text.PlainText
}
