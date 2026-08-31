import QtQuick
import qs.Commons

// A simple full-width button that opens the backend's config file in the
// user's editor/terminal (via `omarchy launch config editor`). `enabled`
// dims the button and ignores clicks.
Item {
  id: sb
  required property string label
  required property color foreground
  required property string fontFamily
  property bool enabled: true

  signal clicked()

  property bool _hover: false

  implicitHeight: contentRow.implicitHeight + Style.space(10)

  Rectangle {
    anchors.fill: parent
    radius: Style.space(4)
    color: (sb.enabled && sb._hover)
      ? Style.hoverBorderFor(sb.foreground, Color.accent)
      : Style.normalBorderFor(sb.foreground, Color.accent)
    border.color: Qt.darker(sb.foreground, 1.7)
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
    color: sb.foreground
    font.family: sb.fontFamily
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
