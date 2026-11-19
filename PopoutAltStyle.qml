import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import QtQuick.Effects

import qs.Common
import qs.Widgets
import qs.DCommon.Widgets
import qs.Services

Column {
    id: altRoot
    property var root: null
    width: parent ? parent.width : (root ? root.popoutWidth : 380)
            spacing: Theme.spacingM

            // GPU Name Div
            Rectangle {
                width: parent.width
                height: 48
                radius: 16
                color: Theme.withAlpha(Theme.surfaceContainerHigh, Theme.popupTransparency)
                
                border.width: 1
                border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)

                Row {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.spacingM
                    spacing: 12
                    
                    DIcon { 
                        name: "memory"
                        size: 20
                        color: Theme.primary
                        anchors.verticalCenter: parent.verticalCenter 
                    }
                    
                    StyledText { 
                        text: root.cleanGpuName
                        font.pixelSize: Theme.fontSizeMedium
                        font.bold: true
                        color: Theme.surfaceText
                        anchors.verticalCenter: parent.verticalCenter 
                    }
                }
            }

            // Main stats
            Row {
                width: parent.width
                spacing: Theme.spacingM

                StatCard {
                    width: (parent.width - Theme.spacingM) / 2
                    color: Theme.withAlpha(Theme.surfaceContainerHigh, Theme.popupTransparency) // Transparency added
                    iconName: "speed"
                    iconColor: Theme.primary
                    label: "GPU"
                    valueText: `${root.gpuUsage.toFixed(0)}%`
                    progressValue: root.gpuUsage
                }

                StatCard {
                    width: (parent.width - Theme.spacingM) / 2
                    color: Theme.withAlpha(Theme.surfaceContainerHigh, Theme.popupTransparency) // Transparency added
                    iconName: "memory"
                    iconColor: Theme.secondary
                    label: "VRAM"
                    valueText: `${(root.vramUsed / 1024).toFixed(1)} GiB`
                    progressValue: root.vramPercent
                }
            }

            // Temperature & Power Row
            Row {
                width: parent.width
                spacing: Theme.spacingS

                // Temperature chip
                Rectangle {
                    visible: root.temperature > 0
                    width: (parent.width - Theme.spacingS) / 2
                    height: 48
                    radius: 12
                    color: root.temperature > 80 ? Theme.withAlpha(Theme.errorHover, Theme.popupTransparency) : Theme.withAlpha(Theme.surfaceContainerHigh, Theme.popupTransparency)

                    border.width: 1
                    border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)

                    Row {
                        anchors.centerIn: parent
                        spacing: Theme.spacingS

                        DIcon {
                            name: "thermostat"
                            size: 22
                            color: root.temperature > 80 ? Theme.error : Theme.secondary
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        StyledText {
                            text: `${root.temperature}°C`
                            color: root.temperature > 80 ? Theme.error : Theme.surfaceText
                            font.pixelSize: Theme.fontSizeMedium
                            font.weight: Font.Bold
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                }

                // Power chip
                Rectangle {
                    visible: root.powerUsage > 0
                    width: (parent.width - Theme.spacingS) / 2
                    height: 48
                    radius: 12
                    color: Theme.withAlpha(Theme.surfaceContainerHigh, Theme.popupTransparency)

                    border.width: 1
                    border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)

                    Row {
                        anchors.centerIn: parent
                        spacing: Theme.spacingS

                        DIcon {
                            name: "bolt"
                            size: 22
                            color: Theme.secondary
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        StyledText {
                            text: `${root.powerUsage}W`
                            color: Theme.surfaceText
                            font.pixelSize: Theme.fontSizeMedium
                            font.weight: Font.Bold
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                }
            }

            // Engine activity section
            Rectangle {
                visible: root.gfxUsage > 0 || root.memUsage > 0 || root.mediaUsage > 0
                width: parent.width
                height: engineContent.height + Theme.spacingM * 2
                radius: Theme.cornerRadius
                color: Theme.withAlpha(Theme.surfaceContainerHigh, Theme.popupTransparency)

                border.width: 1
                border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)

                Column {
                    id: engineContent
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: Theme.spacingM
                    spacing: Theme.spacingS

                    Row {
                        spacing: Theme.spacingS

                        DIcon {
                            name: "speed"
                            size: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        StyledText {
                            text: "Engine Activity"
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Font.Medium
                            color: Theme.surfaceVariantText
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    EngineBar {
                        width: parent.width
                        label: "GFX"
                        value: root.gfxUsage
                        barColor: Theme.primary
                    }

                    EngineBar {
                        width: parent.width
                        label: "MEM"
                        value: root.memUsage
                        barColor: Theme.secondary
                    }

                    EngineBar {
                        width: parent.width
                        label: "Media"
                        value: root.mediaUsage
                        barColor: Theme.info
                    }
                }
            }            
            
            // Process list section (Synced with DMS)
            Rectangle {
                visible: root.gfxUsage > 0 || root.memUsage > 0 || root.mediaUsage > 0
                width: parent.width
                height: altProcessItems.height + Theme.spacingM * 2
                radius: Theme.cornerRadius
                color: Theme.withAlpha(Theme.surfaceContainerHigh, Theme.popupTransparency)

                border.width: 1
                border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)

                Column {
                    id: altProcessItems
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: Theme.spacingM
                    spacing: Theme.spacingS

                    Row {
                        spacing: Theme.spacingS

                        DIcon {
                            name: "apps"
                            size: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        StyledText {
                            text: `GPU Processes (${root.processes.length})`
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Font.Medium
                            color: Theme.surfaceVariantText
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Item { width: Theme.spacingS; height: 1 }

                        DIcon {
                            visible: !!root.toggleProcessList
                            name: "open_in_new"
                            size: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                            opacity: altProcHeaderMouse.containsMouse ? 1 : 0.6
                            anchors.verticalCenter: parent.verticalCenter
                            
                            MouseArea {
                                id: altProcHeaderMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.toggleProcessList()
                            }
                        }
                    }

                    DListView {
                    fadeEdges: false
                    showScrollBar: true
                        width: parent.width
                        height: Math.min(contentHeight, 220)
                        model: root.processes
                        spacing: 2
                        clip: true

                        delegate: Rectangle {
                            id: altProcDelegate
                            clip: true
                            width: ListView.view.width
                            height: 44
                            radius: Theme.cornerRadius
                            Behavior on height { NumberAnimation { duration: Theme.shortDuration; easing.type: Theme.standardEasing } }
                            color: altProcMouseArea.containsMouse
                                ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.06)
                                : "transparent"
                            border.color: altProcMouseArea.containsMouse
                                ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.12)
                                : "transparent"
                            border.width: 1

                            ToolTip.text: modelData.name
                            ToolTip.visible: altProcMouseArea.containsMouse && altProcNameText.implicitWidth > altProcNameText.width
                            ToolTip.delay: 400

                            DRipple { id: altRipple; cornerRadius: parent.radius }

                            MouseArea {
                                id: altProcMouseArea
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                onPressed: altRipple.trigger(mouse.x, mouse.y)
                                onClicked: {
                                    if (mouse.button === Qt.RightButton && root.contextMenuRef) {
                                        let globalPos = mapToItem(root.contextMenuRef.parent, mouse.x, mouse.y);
                                        root.contextMenuRef.show(globalPos.x, globalPos.y, {
                                            pid: modelData.pid,
                                            name: modelData.name,
                                            cmdline: modelData.name
                                        }, false); // HIDDEN PID
                                    }
                                }
                            }

                            Row {
                                anchors.fill: parent
                                anchors.leftMargin: Theme.spacingS
                                anchors.rightMargin: Theme.spacingS
                                spacing: Theme.spacingS

                                // Process name column
                                Item {
                                    width: parent.width - altVramBadge.width - altGfxBadge.width - altCpuBadge.width - Theme.spacingS * 3
                                    height: parent.height

                                    Row {
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: Theme.spacingS

                                        Rectangle {
                                            id: altAppIconContainer
                                            width: 24
                                            height: 24
                                            radius: 6
                                            color: Theme.surfaceContainerHighest || Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.1)
                                            anchors.verticalCenter: parent.verticalCenter

                                            readonly property string iconUrl: root.resolveAppIcon(modelData.name, modelData.pid)

                                            Image {
                                                id: altRealAppIcon
                                                anchors.fill: parent
                                                anchors.margins: 2
                                                source: altAppIconContainer.iconUrl
                                                fillMode: Image.PreserveAspectFit
                                                smooth: true
                                                mipmap: true
                                                asynchronous: true
                                                visible: status === Image.Ready && source !== ""
                                            }

                                            DIcon {
                                                anchors.centerIn: parent
                                                name: root.processCategoryIcon(modelData.name)
                                                size: 14
                                                color: Theme.surfaceText
                                                opacity: 0.85
                                                visible: !altRealAppIcon.visible
                                            }
                                        }

                                        StyledText {
                                            id: altProcNameText
                                            text: modelData.name
                                            font.pixelSize: Theme.fontSizeSmall
                                            font.weight: Font.Medium
                                            color: Theme.surfaceText
                                            elide: Text.ElideRight
                                            width: parent.width - altAppIconContainer.width - Theme.spacingS
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                    }
                                }

                                // VRAM badge
                                Rectangle {
                                    id: altVramBadge
                                    width: 95
                                    height: 24
                                    radius: Theme.cornerRadius
                                    property real procVramPercent: root.vramTotal > 0 ? ((modelData.vramUnit === "GiB" ? modelData.vram * 1024 : modelData.vram) / root.vramTotal * 100) : 0
                                    color: Theme.withAlpha(root.getUsageColor(procVramPercent), 0.15)
                                    anchors.verticalCenter: parent.verticalCenter

                                    Row {
                                        anchors.centerIn: parent
                                        spacing: Theme.spacingXS

                                        DIcon {
                                            name: "memory"
                                            size: Theme.fontSizeSmall
                                            color: root.getUsageColor(altVramBadge.procVramPercent)
                                            anchors.verticalCenter: parent.verticalCenter
                                        }

                                        StyledText {
                                            text: `${modelData.vram} ${modelData.vramUnit}`
                                            font.pixelSize: Theme.fontSizeSmall
                                            font.weight: Font.Bold
                                            color: root.getUsageColor(altVramBadge.procVramPercent)
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                    }
                                }

                                // GFX badge
                                Rectangle {
                                    id: altGfxBadge
                                    width: 64
                                    height: 24
                                    radius: Theme.cornerRadius
                                    color: Theme.withAlpha(root.getUsageColor(modelData.gfx), 0.15)
                                    anchors.verticalCenter: parent.verticalCenter

                                    Row {
                                        anchors.centerIn: parent
                                        spacing: Theme.spacingXS

                                        DIcon {
                                            name: "speed"
                                            size: Theme.fontSizeSmall
                                            color: root.getUsageColor(modelData.gfx)
                                            anchors.verticalCenter: parent.verticalCenter
                                        }

                                        StyledText {
                                            text: modelData.gfx > 0 ? `${modelData.gfx}%` : "—"
                                            font.pixelSize: Theme.fontSizeSmall
                                            font.weight: Font.Bold
                                            color: root.getUsageColor(modelData.gfx)
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                    }
                                }

                                // CPU badge
                                Rectangle {
                                    id: altCpuBadge
                                    width: 64
                                    height: 24
                                    radius: Theme.cornerRadius
                                    color: Qt.rgba(Theme.surfaceText.r, Theme.surfaceText.g, Theme.surfaceText.b, 0.06)
                                    anchors.verticalCenter: parent.verticalCenter

                                    Row {
                                        anchors.centerIn: parent
                                        spacing: Theme.spacingXS

                                        DIcon {
                                            name: "developer_board"
                                            size: Theme.fontSizeSmall
                                            color: Theme.surfaceVariantText
                                            anchors.verticalCenter: parent.verticalCenter
                                        }

                                        StyledText {
                                            text: modelData.cpu > 0 ? `${modelData.cpu}%` : "—"
                                            font.pixelSize: Theme.fontSizeSmall
                                            font.weight: Font.Bold
                                            color: Theme.surfaceVariantText
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
