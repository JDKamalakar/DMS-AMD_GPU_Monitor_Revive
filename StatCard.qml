import QtQuick
import qs.Common
import qs.Widgets
import qs.DCommon.Widgets

    // Stat card component for alt style
    Rectangle {
        id: statCardRoot
        width: 100
        height: 100
        radius: 16
        color: Theme.surfaceContainerHigh

        readonly property color usageColor: {
        const val = statCardRoot.progressValue;
        if (val >= 85) return Theme.tempDanger || Theme.error;
        if (val >= 70) return Theme.tempWarning || Theme.warning;
        return Theme.primary;
    }
        readonly property bool isElevated: statCardRoot.progressValue > 70

        border.width: 1
        border.color: isElevated ? Qt.rgba(usageColor.r, usageColor.g, usageColor.b, 0.4) : Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)

        property string iconName: ""
        property color iconColor: Theme.primary
        property string label: ""
        property string valueText: ""
        property real progressValue: 0  // 0-100

        Column {
            anchors.fill: parent
            anchors.margins: Theme.spacingM
            spacing: Theme.spacingS

            Row {
                spacing: Theme.spacingS

                DIcon {
                    name: statCardRoot.iconName
                    size: 20
                    color: statCardRoot.isElevated ? statCardRoot.usageColor : statCardRoot.iconColor
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    text: statCardRoot.label
                    color: statCardRoot.isElevated ? statCardRoot.usageColor : Theme.surfaceVariantText
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Font.Medium
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            StyledText {
                text: statCardRoot.valueText
                color: statCardRoot.isElevated ? statCardRoot.usageColor : Theme.surfaceText
                font.pixelSize: Theme.fontSizeXXLarge
                font.weight: Font.Bold
            }

            Rectangle {
                width: parent.width
                height: 4
                radius: 2
                color: Theme.surfaceContainerHighest

                Rectangle {
                    width: parent.width * (statCardRoot.progressValue / 100)
                    height: parent.height
                    radius: 2
                    color: statCardRoot.usageColor

                    Behavior on width {
                        NumberAnimation { duration: Theme.mediumDuration; easing.type: Theme.standardEasing }
                    }
                }
            }
        }
    }

