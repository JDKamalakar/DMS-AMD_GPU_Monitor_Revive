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

Rectangle {
    id: duxPopoutContent
    property var root: null
    width: parent ? parent.width : root.popoutWidth
    implicitHeight: duxLayout.implicitHeight
    color: "transparent"

    function focusSearch() {
        Qt.callLater(() => {
            duxSearchField.forceActiveFocus();
        });
    }

    onVisibleChanged: {
        if (visible) {
            focusSearch();
        }
    }
    Component.onCompleted: {
        focusSearch();
    }

    // Capture typing whenever popout has focus
    Keys.forwardTo: [duxSearchField]
    Keys.onPressed: event => {
        if (root && root.contextMenuRef && root.contextMenuRef.visible) return;
        if (event.key === Qt.Key_Escape) {
            if (duxSearchField.text.length > 0) {
                duxSearchField.text = "";
                event.accepted = true;
                return;
            }
        }
        if (!duxSearchField.inputFocused && event.text && event.text.length > 0 && event.key !== Qt.Key_Return && event.key !== Qt.Key_Enter && event.key !== Qt.Key_Tab && event.key !== Qt.Key_Backtab) {
            duxSearchField.forceActiveFocus();
            duxSearchField.insertText(event.text);
            event.accepted = true;
        }
    }

            property string searchText: ""
            property int filterIndex: 0 // 0: All, 1: Active, 2: 3D/Compute, 3: High VRAM
            property string sortColumn: (root && root.processSort) ? root.processSort : "vram"
            property bool sortAsc: false
            property int expandedPid: -1

            readonly property var rawProcesses: (root && root.processes) ? root.processes : []

            readonly property var displayProcesses: {
                let list = rawProcesses.slice();

                // 1. Search text filter
                if (searchText.trim().length > 0) {
                    const q = searchText.trim().toLowerCase();
                    list = list.filter(p => (p.name || "").toLowerCase().includes(q) || String(p.pid).includes(q));
                }

                // 2. Filter chip
                if (filterIndex === 1) { // Active
                    list = list.filter(p => (p.gfx || 0) > 0 || (p.cpu || 0) > 0);
                } else if (filterIndex === 2) { // 3D/Compute
                    list = list.filter(p => (p.gfx || 0) > 0);
                } else if (filterIndex === 3) { // High VRAM (> 500 MiB)
                    list = list.filter(p => {
                        const mb = p.vramUnit === "GiB" ? (p.vram * 1024) : p.vram;
                        return mb >= 500;
                    });
                }

                // 3. Sorting
                list.sort((a, b) => {
                    let valA = 0, valB = 0;
                    if (sortColumn === "name") {
                        valA = (a.name || "").toLowerCase();
                        valB = (b.name || "").toLowerCase();
                        return sortAsc ? valA.localeCompare(valB) : valB.localeCompare(valA);
                    } else if (sortColumn === "pid") {
                        valA = a.pid || 0;
                        valB = b.pid || 0;
                    } else if (sortColumn === "gfx") {
                        valA = a.gfx || 0;
                        valB = b.gfx || 0;
                    } else if (sortColumn === "vram") {
                        valA = a.vramUnit === "GiB" ? (a.vram * 1024) : (a.vram || 0);
                        valB = b.vramUnit === "GiB" ? (b.vram * 1024) : (b.vram || 0);
                    } else { // default to vram
                        valA = a.vramUnit === "GiB" ? (a.vram * 1024) : (a.vram || 0);
                        valB = b.vramUnit === "GiB" ? (b.vram * 1024) : (b.vram || 0);
                    }
                    return sortAsc ? (valA - valB) : (valB - valA);
                });

                return list;
            }

            ColumnLayout {
                id: duxLayout
                width: parent.width
                spacing: Theme.spacingM

                // 1. System Header (Matches ProcessSystemHeader.qml)
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacingS

                    SystemLogo {
                        Layout.preferredWidth: Theme.iconSize || 20
                        Layout.preferredHeight: Theme.iconSize || 20
                        colorOverride: Theme.primary
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: {
                            const host = (typeof DgopService !== "undefined" && DgopService && DgopService.hostname) ? DgopService.hostname : "localhost";
                            const distro = (typeof DgopService !== "undefined" && DgopService && DgopService.distribution) ? DgopService.distribution : "Linux";
                            const uptimeStr = (typeof DgopService !== "undefined" && DgopService && DgopService.shortUptime) ? DgopService.shortUptime.slice(2).trim() : "--";
                            return host + " · " + distro + " · " + I18n.tr("Uptime") + ": " + uptimeStr + " · " + I18n.tr("%1 procs", "%1 is a count").arg(duxPopoutContent.rawProcesses.length);
                        }
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.onSurfaceVariant || Theme.surfaceVariantText
                        elide: Text.ElideRight
                    }

                    StyledText {
                        visible: (root && root.temperature > 0)
                        text: I18n.tr("GPU %1").arg((root ? root.temperature : 0) + "°C")
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: Font.Medium
                        color: (root && root.temperature > 85) ? Theme.error : (Theme.onSurfaceVariant || Theme.surfaceVariantText)
                    }

                    StyledText {
                        visible: (root && root.powerUsage > 0)
                        text: `${root.powerUsage}W`
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: Font.Medium
                        color: Theme.onSurfaceVariant || Theme.surfaceVariantText
                    }
                }

                // 2. Summary Performance Cards (Matches ProcessSummary.qml / PerformanceCard.qml)
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacingS

                    // GPU Utilization Card
                    Rectangle {
                        id: duxGpuCard
                        Layout.fillWidth: true
                        Layout.preferredHeight: 110
                        radius: Theme.cornerRadiusL
                        color: Theme.foregroundColor ? Theme.foregroundColor(Theme.cardSurface) : Theme.cardSurface
                        border.width: Theme.layerOutlineWidth || 1
                        border.color: Theme.outlineMedium || Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)
                        clip: true

                        DSparkline {
                            anchors.fill: parent
                            anchors.topMargin: 24
                            values: (root && root.gpuUsageHistory && root.gpuUsageHistory.length >= 2) ? root.gpuUsageHistory : [0, (root ? root.gpuUsage : 0)]
                            lineColor: Theme.primary
                            maximum: 100
                            curved: false
                            lineWidth: 2
                            fillOpacity: 0.2
                        }

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: Theme.spacingM
                            spacing: Theme.spacingXS

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Theme.spacingS

                                DIcon {
                                    name: "speed"
                                    size: Theme.iconSizeSmall || 16
                                    color: Theme.primary
                                }

                                StyledText {
                                    text: I18n.tr("GPU")
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.weight: Theme.fontWeightMedium || Font.Medium
                                    color: Theme.surfaceText
                                }

                                Item { Layout.fillWidth: true }

                                StyledText {
                                    text: (root && root.temperature > 0) ? (root.temperature + "°C") : ""
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: (root && root.temperature > 85) ? Theme.error : Theme.surfaceVariantText
                                    visible: text.length > 0
                                }
                            }

                            Item { Layout.fillHeight: true }

                            NumericText {
                                text: (root ? root.gpuUsage.toFixed(1) : "0.0") + "%"
                                font.pixelSize: Theme.fontSizeXLarge || 22
                                font.weight: Theme.fontWeightMedium || Font.Medium
                                color: Theme.surfaceText
                            }
                        }
                    }

                    // VRAM Card
                    Rectangle {
                        id: duxVramCard
                        Layout.fillWidth: true
                        Layout.preferredHeight: 110
                        radius: Theme.cornerRadiusL
                        color: Theme.foregroundColor ? Theme.foregroundColor(Theme.cardSurface) : Theme.cardSurface
                        border.width: Theme.layerOutlineWidth || 1
                        border.color: Theme.outlineMedium || Qt.rgba(Theme.secondary.r, Theme.secondary.g, Theme.secondary.b, 0.15)
                        clip: true

                        DSparkline {
                            anchors.fill: parent
                            anchors.topMargin: 24
                            values: (root && root.vramUsageHistory && root.vramUsageHistory.length >= 2) ? root.vramUsageHistory : [0, (root ? root.vramPercent : 0)]
                            lineColor: Theme.secondary
                            maximum: 100
                            curved: false
                            lineWidth: 2
                            fillOpacity: 0.2
                        }

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: Theme.spacingM
                            spacing: Theme.spacingXS

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Theme.spacingS

                                DIcon {
                                    name: "developer_board"
                                    size: Theme.iconSizeSmall || 16
                                    color: Theme.secondary
                                }

                                StyledText {
                                    text: I18n.tr("Memory")
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.weight: Theme.fontWeightMedium || Font.Medium
                                    color: Theme.surfaceText
                                }

                                Item { Layout.fillWidth: true }

                                StyledText {
                                    text: (root && root.vramTotal > 0) ? (root.vramPercent.toFixed(0) + "%") : ""
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceVariantText
                                    visible: text.length > 0
                                }
                            }

                            Item { Layout.fillHeight: true }

                            NumericText {
                                text: ((root ? root.vramUsed : 0) / 1024).toFixed(1) + " GB / " + ((root ? root.vramTotal : 0) / 1024).toFixed(1) + " GB"
                                font.pixelSize: Theme.fontSizeXLarge || 22
                                font.weight: Theme.fontWeightMedium || Font.Medium
                                color: Theme.surfaceText
                            }
                        }
                    }
                }

                // 3. Search Field + Filter Chips Row (Matches DSearchField + DFilterChips in Dux)
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacingM

                    Rectangle {
                        id: duxSearchBox
                        Layout.fillWidth: true
                        Layout.minimumWidth: Theme.fontSizeMedium * 8
                        Layout.preferredHeight: Theme.buttonHeightS
                        radius: height / 2
                        color: Theme.chipSurface || "#2a282f"
                        border.color: (duxSearchField && duxSearchField.inputFocused) ? Theme.primary : (Theme.outlineVariant || "#49454f")
                        border.width: (duxSearchField && duxSearchField.inputFocused) ? 2 : 1
                        clip: true

                        DSearchField {
                            id: duxSearchField
                            anchors.fill: parent
                            backgroundColor: "transparent"
                            borderWidth: 0
                            focusedBorderWidth: 0
                            cornerRadius: duxSearchBox.radius
                            radius: duxSearchBox.radius
                            placeholderText: I18n.tr("Search", "search field placeholder") + "…"
                            text: duxPopoutContent.searchText
                            onTextChanged: duxPopoutContent.searchText = text
                        }
                    }

                    DFilterChips {
                        id: duxFilterChips
                        Layout.preferredWidth: singleRowWidth
                        model: [I18n.tr("All"), I18n.tr("Active"), I18n.tr("3D"), I18n.tr("VRAM")]
                        currentIndex: duxPopoutContent.filterIndex
                        showCounts: false
                        chipPadding: Theme.spacingM
                        onSelectionChanged: index => {
                            duxPopoutContent.filterIndex = index;
                        }
                    }
                }

                // 4. Table Header (Name, GPU, VRAM, PID)
                Rectangle {
                    Layout.fillWidth: true
                    height: Theme.buttonHeightXS || 28
                    radius: Theme.cornerRadiusS
                    color: Theme.withAlpha(Theme.surfaceContainerHigh, 0.4)

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.spacingM
                        anchors.rightMargin: Theme.spacingM
                        spacing: Theme.spacingS

                        // Name Header
                        Item {
                            Layout.fillWidth: true
                            height: parent.height

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (duxPopoutContent.sortColumn === "name") {
                                        duxPopoutContent.sortAsc = !duxPopoutContent.sortAsc;
                                    } else {
                                        duxPopoutContent.sortColumn = "name";
                                        duxPopoutContent.sortAsc = true;
                                    }
                                }
                            }

                            Row {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: Theme.spacingXS

                                StyledText {
                                    text: I18n.tr("Name")
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.weight: Font.Medium
                                    color: duxPopoutContent.sortColumn === "name" ? Theme.primary : Theme.surfaceVariantText
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                DIcon {
                                    visible: duxPopoutContent.sortColumn === "name"
                                    name: duxPopoutContent.sortAsc ? "arrow_upward" : "arrow_downward"
                                    size: 14
                                    color: Theme.primary
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                        }

                        // GPU Usage Header
                        Item {
                            Layout.preferredWidth: 64
                            height: parent.height

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (duxPopoutContent.sortColumn === "gfx") {
                                        duxPopoutContent.sortAsc = !duxPopoutContent.sortAsc;
                                    } else {
                                        duxPopoutContent.sortColumn = "gfx";
                                        duxPopoutContent.sortAsc = false;
                                    }
                                }
                            }

                            Row {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: Theme.spacingXS

                                StyledText {
                                    text: I18n.tr("GPU")
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.weight: Font.Medium
                                    color: duxPopoutContent.sortColumn === "gfx" ? Theme.primary : Theme.surfaceVariantText
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                DIcon {
                                    visible: duxPopoutContent.sortColumn === "gfx"
                                    name: duxPopoutContent.sortAsc ? "arrow_upward" : "arrow_downward"
                                    size: 14
                                    color: Theme.primary
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                        }

                        // VRAM Header
                        Item {
                            Layout.preferredWidth: 80
                            height: parent.height

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (duxPopoutContent.sortColumn === "vram") {
                                        duxPopoutContent.sortAsc = !duxPopoutContent.sortAsc;
                                    } else {
                                        duxPopoutContent.sortColumn = "vram";
                                        duxPopoutContent.sortAsc = false;
                                    }
                                }
                            }

                            Row {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: Theme.spacingXS

                                StyledText {
                                    text: I18n.tr("VRAM")
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.weight: Font.Medium
                                    color: duxPopoutContent.sortColumn === "vram" ? Theme.primary : Theme.surfaceVariantText
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                DIcon {
                                    visible: duxPopoutContent.sortColumn === "vram"
                                    name: duxPopoutContent.sortAsc ? "arrow_upward" : "arrow_downward"
                                    size: 14
                                    color: Theme.primary
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                        }

                        // PID Header
                        Item {
                            Layout.preferredWidth: 50
                            height: parent.height

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (duxPopoutContent.sortColumn === "pid") {
                                        duxPopoutContent.sortAsc = !duxPopoutContent.sortAsc;
                                    } else {
                                        duxPopoutContent.sortColumn = "pid";
                                        duxPopoutContent.sortAsc = true;
                                    }
                                }
                            }

                            Row {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: Theme.spacingXS

                                StyledText {
                                    text: I18n.tr("PID")
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.weight: Font.Medium
                                    color: duxPopoutContent.sortColumn === "pid" ? Theme.primary : Theme.surfaceVariantText
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                DIcon {
                                    visible: duxPopoutContent.sortColumn === "pid"
                                    name: duxPopoutContent.sortAsc ? "arrow_upward" : "arrow_downward"
                                    size: 14
                                    color: Theme.primary
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                        }
                    }
                }

                // 5. Grouped/Segmented Process Rows (Matches DListItem + ProcessRow styling)
                DListView {
                    fadeEdges: false
                    showScrollBar: true
                    id: duxProcessList
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(Math.max(contentHeight, 52), 260)
                    model: duxPopoutContent.displayProcesses
                    spacing: Theme.groupedListGap || 2
                    clip: true

                    add: Transition {
                        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 180; easing.type: Easing.OutCubic }
                        NumberAnimation { property: "scale"; from: 0.95; to: 1.0; duration: 180; easing.type: Easing.OutCubic }
                    }
                    remove: Transition {
                        NumberAnimation { property: "opacity"; to: 0; duration: 150; easing.type: Easing.InQuad }
                        NumberAnimation { property: "scale"; to: 0.95; duration: 150; easing.type: Easing.InQuad }
                    }
                    displaced: Transition {
                        NumberAnimation { property: "y"; duration: 220; easing.type: Easing.OutCubic }
                        NumberAnimation { property: "opacity"; to: 1; duration: 180 }
                    }

                    delegate: Rectangle {
                        id: duxRowDelegate
                        required property var modelData
                        required property int index

                        readonly property bool isExpanded: duxPopoutContent.expandedPid === modelData.pid
                        readonly property bool isFirst: index === 0
                        readonly property bool isLast: index === (duxProcessList.count - 1)
                        readonly property real outerRad: Theme.groupedListOuterRadius || Theme.cornerRadiusL || 12
                        readonly property real innerRad: Theme.groupedListInnerRadius || Theme.cornerRadiusXS || 4

                        width: ListView.view ? ListView.view.width : duxLayout.width
                        height: isExpanded ? (44 + duxDetailLoader.implicitHeight + Theme.spacingM) : 44
                        clip: true

                        Behavior on height {
                            NumberAnimation { duration: 160; easing.type: Easing.OutQuad }
                        }

                        radius: innerRad
                        topLeftRadius: isFirst ? outerRad : innerRad
                        topRightRadius: isFirst ? outerRad : innerRad
                        bottomLeftRadius: isLast ? outerRad : innerRad
                        bottomRightRadius: isLast ? outerRad : innerRad

                        color: duxRowMouse.containsMouse
                            ? Theme.withAlpha(Theme.surfaceVariant, 0.16)
                            : (Theme.foregroundColor ? Theme.foregroundColor(Theme.cardSurface) : Theme.cardSurface)

                        border.width: Theme.layerOutlineWidth || 1
                        border.color: isExpanded ? Theme.primary : (duxRowMouse.containsMouse ? Theme.outlineMedium : Theme.outlineLight)

                        DRipple {
                            id: duxRipple
                            anchors.fill: parent
                            cornerRadius: duxRowDelegate.radius
                        }

                        MouseArea {
                            id: duxRowMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onPressed: mouse => duxRipple.trigger(mouse.x, mouse.y)
                            onClicked: mouse => {
                                if (mouse.button === Qt.RightButton && root.contextMenuRef) {
                                    const globalPos = mapToItem(root.contextMenuRef.parent, mouse.x, mouse.y);
                                    root.contextMenuRef.show(globalPos.x, globalPos.y, {
                                        pid: modelData.pid,
                                        name: modelData.name,
                                        cmdline: modelData.name
                                    }, true);
                                } else {
                                    duxPopoutContent.expandedPid = isExpanded ? -1 : modelData.pid;
                                }
                            }
                        }

                        Column {
                            anchors.fill: parent

                            // Main Process Row
                            Item {
                                width: parent.width
                                height: 44

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: Theme.spacingM
                                    anchors.rightMargin: Theme.spacingM
                                    spacing: Theme.spacingS

                                    // Real Desktop App Icon in rounded Container
                                    Rectangle {
                                        id: duxAppIconContainer
                                        Layout.preferredWidth: 26
                                        Layout.preferredHeight: 26
                                        radius: 6
                                        color: Theme.surfaceContainerHighest || Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.12)
                                        Layout.alignment: Qt.AlignVCenter

                                        readonly property string iconUrl: root.resolveAppIcon(modelData.name, modelData.pid)

                                        Image {
                                            id: duxRealAppIcon
                                            anchors.fill: parent
                                            anchors.margins: 2
                                            source: duxAppIconContainer.iconUrl
                                            fillMode: Image.PreserveAspectFit
                                            smooth: true
                                            mipmap: true
                                            asynchronous: true
                                            visible: status === Image.Ready && source !== ""
                                        }

                                        DIcon {
                                            anchors.centerIn: parent
                                            name: root.processCategoryIcon(modelData.name)
                                            size: 15
                                            color: Theme.surfaceText
                                            opacity: 0.85
                                            visible: !duxRealAppIcon.visible
                                        }
                                    }

                                    // Process Display Name
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: modelData.name
                                        font.pixelSize: Theme.fontSizeMedium
                                        font.weight: Font.Medium
                                        color: Theme.surfaceText
                                        elide: Text.ElideRight
                                        Layout.alignment: Qt.AlignVCenter
                                    }

                                    // GPU %
                                    NumericText {
                                        Layout.preferredWidth: 64
                                        text: (modelData.gfx || 0).toFixed(1) + "%"
                                        font.pixelSize: Theme.fontSizeSmall
                                        font.weight: Font.Medium
                                        color: root.getUsageColor(modelData.gfx)
                                        horizontalAlignment: Text.AlignRight
                                        Layout.alignment: Qt.AlignVCenter
                                    }

                                    // VRAM
                                    NumericText {
                                        Layout.preferredWidth: 80
                                        text: `${modelData.vram} ${modelData.vramUnit}`
                                        font.pixelSize: Theme.fontSizeSmall
                                        font.weight: Font.Medium
                                        property real procVramPercent: root.vramTotal > 0 ? ((modelData.vramUnit === "GiB" ? modelData.vram * 1024 : modelData.vram) / root.vramTotal * 100) : 0
                                        color: root.getUsageColor(procVramPercent)
                                        horizontalAlignment: Text.AlignRight
                                        Layout.alignment: Qt.AlignVCenter
                                    }

                                    // PID
                                    NumericText {
                                        Layout.preferredWidth: 50
                                        text: String(modelData.pid)
                                        font.pixelSize: Theme.fontSizeSmall
                                        color: Theme.surfaceVariantText
                                        horizontalAlignment: Text.AlignRight
                                        Layout.alignment: Qt.AlignVCenter
                                    }
                                }
                            }

                            // Detail Strip when expanded (matching ProcessDetailStrip screenshot)
                            Item {
                                width: parent.width
                                height: duxRowDelegate.isExpanded ? (duxDetailLoader.implicitHeight + Theme.spacingM) : 0
                                visible: duxRowDelegate.isExpanded

                                Loader {
                                    id: duxDetailLoader
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.margins: Theme.spacingM
                                    anchors.top: parent.top
                                    anchors.topMargin: Theme.spacingXS
                                    active: duxRowDelegate.isExpanded
                                    visible: duxRowDelegate.isExpanded
                                    sourceComponent: DuxProcessDetailView {
                                        root: duxPopoutContent.root
                                        processData: modelData
                                    }
                                }
                            }
                        }
                    }

                    StyledText {
                        anchors.centerIn: parent
                        text: I18n.tr("No matching processes")
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                        visible: duxProcessList.count === 0
                    }
                }
            }
        }
