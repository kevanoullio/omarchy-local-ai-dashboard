import QtQuick
import qs.Commons

// A value text used for service detail rows (Status, Version, API, ...).
Text {
  id: root
  required property color foreground
  required property string fontFamily

  color: foreground
  font.family: fontFamily
  font.pixelSize: Style.font.bodySmall
  textFormat: Text.PlainText
}
