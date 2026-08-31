import QtQuick
import qs.Commons

// A clickable backend selector: name + live status below. The active card
// is highlighted; `highlighted` drives the cursor-hover emphasis.
Item {
  id: root
  required property string label
  required property string statusText
  required property color statusColor
  required property color foreground
  required property string fontFamily
  required property bool active
  property bool highlighted: false

  signal clicked()
  signal hovered(bool on)

  property bool _hover: false

  implicitWidth: Math.max(nameLabel.implicitWidth, statusLabel.implicitWidth) + Style.space(24)
  implicitHeight: contentCol.implicitHeight + Style.space(14)

  Rectangle {
    anchors.fill: parent
    radius: Style.space(6)
    color: {
      if (root.highlighted && parent._hover)
        return Style.hoverBorderFor(root.foreground, Color.accent)
      if (root.active)
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
      color: root.statusColor
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
        text: root.label
        color: root.statusColor
        font.family: root.fontFamily
        font.pixelSize: Style.font.title
        font.bold: true
        textFormat: Text.PlainText
        elide: Text.ElideRight
      }

      Text {
        id: statusLabel
        text: root.statusText.toUpperCase()
        color: root.statusColor
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
