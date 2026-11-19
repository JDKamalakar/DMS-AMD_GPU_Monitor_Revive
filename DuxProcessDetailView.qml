import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import QtQuick.Effects

import qs.Common
import qs.Widgets
import qs.DCommon.Widgets
import qs.Services

Rectangle {
    id: detailRoot

    property var root: null
    required property var processData
    readonly property int pid: (processData && processData.pid) ? Number(processData.pid) : 0
    readonly property string procName: (processData && processData.name) ? String(processData.name) : ""
    property bool showHeader: true

    property int activeTab: 0 // 0: Overview, 1: Resources, 2: Details
    property string fullCmdline: ""
    property string procUsername: ""
    property string procStartTime: ""
    property string procThreads: "1"
    property string procOpenFiles: "—"
    property string procMemoryBytes: ""
    property string procReadTotal: "—"
    property string procWriteTotal: "—"
    property string procCpuTime: "0:00"
    property string procNice: "0"
    property string procStatus: "S"
    property string procPPid: "1"
    property string procTty: "—"
    property string procExe: ""
    property string procCwd: ""

    // Helper functions for parsing
    function extractProcField(text, fieldName) {
        if (!text) return "";
        const lines = text.split("\n");
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i];
            if (line.startsWith(fieldName + ":")) {
                return line.substring(fieldName.length + 1).trim();
            }
        }
        return "";
    }

    function formatCmdline(text) {
        if (!text) return "";
        return text.replace(/\u0000/g, " ").trim();
    }

    function processCategoryIcon(command) {
        if (root && typeof root.processCategoryIcon === "function") {
            return root.processCategoryIcon(command);
        }
        if (!command) return "terminal";
        const c = command.toLowerCase();
        if (c.includes("chrome") || c.includes("firefox") || c.includes("brave") || c.includes("browser") || c.includes("zen")) return "language";
        if (c.includes("steam") || c.includes("heroic") || c.includes("lutris") || c.includes("game") || c.includes("wine") || c.includes("proton")) return "sports_esports";
        if (c.includes("code") || c.includes("zed") || c.includes("studio") || c.includes("neovim") || c.includes("vim") || c.includes("emacs")) return "terminal";
        if (c.includes("discord") || c.includes("slack") || c.includes("telegram") || c.includes("signal") || c.includes("element")) return "chat";
        if (c.includes("vlc") || c.includes("mpv") || c.includes("spotify") || c.includes("music") || c.includes("video")) return "play_circle";
        if (c.includes("blender") || c.includes("gimp") || c.includes("inkscape") || c.includes("krita") || c.includes("obs")) return "palette";
        if (c.includes("term") || c.includes("kitty") || c.includes("alacritty") || c.includes("ghostty") || c.includes("bash") || c.includes("zsh") || c.includes("fish")) return "terminal";
        return "apps";
    }

    function resolveAppIcon(command, pid) {
        if (root && typeof root.resolveAppIcon === "function") {
            return root.resolveAppIcon(command, pid);
        }
        return "";
    }

    implicitHeight: detailBody.implicitHeight + Theme.spacingM * 2
    radius: Theme.cornerRadiusM || 8
    color: Theme.withAlpha(Theme.surfaceContainerHigh || Theme.surfaceContainerHighest, Theme.popupTransparency || 0.6)
    border.width: Theme.layerOutlineWidth || 1
    border.color: Theme.outlineMedium || Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)
    clip: true

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onClicked: {}
    }

    FileView {
        id: cmdlineReader
        path: detailRoot.pid > 0 ? ("/proc/" + detailRoot.pid + "/cmdline") : ""
        onLoaded: {
            const raw = text();
            detailRoot.fullCmdline = detailRoot.formatCmdline(raw) || detailRoot.procName;
        }
    }

    FileView {
        id: statusReader
        path: detailRoot.pid > 0 ? ("/proc/" + detailRoot.pid + "/status") : ""
        onLoaded: {
            const txt = text();
            detailRoot.procThreads = detailRoot.extractProcField(txt, "Threads") || "1";
            detailRoot.procPPid = detailRoot.extractProcField(txt, "PPid") || "1";
            detailRoot.procStatus = detailRoot.extractProcField(txt, "State") || "S";
            const vmRss = detailRoot.extractProcField(txt, "VmRSS");
            if (vmRss) {
                const kb = parseInt(vmRss.replace(/[^0-9]/g, ""));
                if (!isNaN(kb) && kb > 0) {
                    detailRoot.procMemoryBytes = kb >= 1048576 ? (kb / 1048576).toFixed(1) + " GiB" : (kb / 1024).toFixed(1) + " MiB";
                }
            }
            const uidLine = detailRoot.extractProcField(txt, "Uid");
            if (uidLine) {
                const uid = uidLine.split("\t")[0] || uidLine.split(" ")[0];
                if (uid === "0") detailRoot.procUsername = "root";
                else if (typeof UserInfoService !== "undefined" && UserInfoService && UserInfoService.username) detailRoot.procUsername = UserInfoService.username;
                else detailRoot.procUsername = "user";
            }
        }
    }

    FileView {
        id: ioReader
        path: detailRoot.pid > 0 ? ("/proc/" + detailRoot.pid + "/io") : ""
        onLoaded: {
            const txt = text();
            const rb = detailRoot.extractProcField(txt, "read_bytes");
            const wb = detailRoot.extractProcField(txt, "write_bytes");
            if (rb) {
                const b = parseInt(rb);
                if (!isNaN(b)) detailRoot.procReadTotal = b >= 1073741824 ? (b / 1073741824).toFixed(1) + " GiB" : (b >= 1048576 ? (b / 1048576).toFixed(1) + " MiB" : (b / 1024).toFixed(0) + " KiB");
            }
            if (wb) {
                const b = parseInt(wb);
                if (!isNaN(b)) detailRoot.procWriteTotal = b >= 1073741824 ? (b / 1073741824).toFixed(1) + " GiB" : (b >= 1048576 ? (b / 1048576).toFixed(1) + " MiB" : (b / 1024).toFixed(0) + " KiB");
            }
        }
    }

    Process {
        id: statReaderProc
        command: ["sh", "-c", `if [ -d /proc/${detailRoot.pid}/fd ]; then ls /proc/${detailRoot.pid}/fd 2>/dev/null | wc -l; fi`]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                const cnt = text.trim();
                if (cnt && !isNaN(parseInt(cnt))) detailRoot.procOpenFiles = cnt;
            }
        }
    }

    Component.onCompleted: {
        if (detailRoot.pid > 0) statReaderProc.running = true;
    }

    ColumnLayout {
        id: detailBody
        anchors.fill: parent
        anchors.margins: Theme.spacingM
        spacing: Theme.spacingM

        // 1. Process Header: Large App Icon, Name, Command (visible when showHeader is true, e.g. in DMS popout)
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingM
            visible: detailRoot.showHeader

            Rectangle {
                Layout.preferredWidth: Theme.iconButtonSize || 36
                Layout.preferredHeight: Theme.iconButtonSize || 36
                radius: Theme.cornerRadiusM || 8
                color: Theme.surfaceContainerHighest || Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)

                readonly property string appIconPath: detailRoot.resolveAppIcon(detailRoot.fullCmdline || detailRoot.procName, detailRoot.pid)

                Image {
                    id: headerAppIcon
                    anchors.fill: parent
                    anchors.margins: 4
                    source: parent.appIconPath
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    mipmap: true
                    asynchronous: true
                    visible: status === Image.Ready && source !== ""
                }

                DIcon {
                    anchors.centerIn: parent
                    name: detailRoot.processCategoryIcon(detailRoot.procName)
                    size: Theme.iconSizeMedium || 22
                    color: Theme.primary
                    visible: !headerAppIcon.visible
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                StyledText {
                    Layout.fillWidth: true
                    text: detailRoot.procName
                    font.pixelSize: Theme.fontSizeLarge || 16
                    font.weight: Font.DemiBold
                    color: Theme.surfaceText
                    elide: Text.ElideRight
                }

                StyledText {
                    Layout.fillWidth: true
                    text: (detailRoot.fullCmdline || detailRoot.procName).replace(/\s+/g, " ")
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    elide: Text.ElideRight
                }
            }
        }

        // 2. Metadata Info Chips Row (centered with first/mid/last segmented styling like list items)
        RowLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignHCenter

            Item { Layout.fillWidth: true }

            Row {
                id: chipsRow
                spacing: 1

                readonly property real outerRad: Theme.groupedListOuterRadius || Theme.cornerRadiusL || 10
                readonly property real innerRad: 4

                // Helper to get chip count
                readonly property var chipList: [
                    { id: "user", visible: detailRoot.procUsername !== "", icon: "person", iconColor: Theme.surfaceVariantText, text: detailRoot.procUsername },
                    { id: "pid", visible: true, icon: "tag", iconColor: Theme.surfaceVariantText, text: "PID " + detailRoot.pid },
                    { id: "vram", visible: true, icon: "developer_board", iconColor: Theme.secondary, text: `${detailRoot.processData.vram || 0} ${detailRoot.processData.vramUnit || 'MiB'}` },
                    { id: "gfx", visible: true, icon: "speed", iconColor: Theme.primary, text: (detailRoot.processData.gfx || 0) + "% GPU" },
                    { id: "status", visible: true, icon: "settings", iconColor: Theme.surfaceVariantText, text: detailRoot.procStatus.startsWith("R") ? I18n.tr("Running") : I18n.tr("Sleeping") }
                ].filter(c => c.visible)

                Repeater {
                    model: chipsRow.chipList

                    Rectangle {
                        required property var modelData
                        required property int index

                        implicitWidth: chipInnerRow.implicitWidth + Theme.spacingM * 2
                        height: Theme.buttonHeightXS || 28
                        radius: chipsRow.innerRad
                        topLeftRadius: index === 0 ? chipsRow.outerRad : chipsRow.innerRad
                        bottomLeftRadius: index === 0 ? chipsRow.outerRad : chipsRow.innerRad
                        topRightRadius: index === (chipsRow.chipList.length - 1) ? chipsRow.outerRad : chipsRow.innerRad
                        bottomRightRadius: index === (chipsRow.chipList.length - 1) ? chipsRow.outerRad : chipsRow.innerRad

                        color: Theme.surfaceContainerHighest || Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.08)
                        border.width: 1
                        border.color: Theme.outlineMedium || Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.12)

                        Row {
                            id: chipInnerRow
                            anchors.centerIn: parent
                            spacing: Theme.spacingXS
                            DIcon {
                                name: modelData.icon
                                size: 14
                                color: modelData.iconColor
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            StyledText {
                                text: modelData.text
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceText
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }
                }
            }

            Item { Layout.fillWidth: true }
        }

        // 3. Tab Bar (Overview, Resources, Details) centered using official Dux DTabBar
        RowLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignHCenter

            Item { Layout.fillWidth: true }

            DTabBar {
                id: tabs
                Layout.preferredWidth: Math.min(detailBody.width, 360)
                Layout.alignment: Qt.AlignHCenter
                showIcons: false
                equalWidthTabs: true
                model: [
                    { text: I18n.tr("Overview") },
                    { text: I18n.tr("Resources") },
                    { text: I18n.tr("Details") }
                ]
                currentIndex: detailRoot.activeTab
                onTabClicked: index => detailRoot.activeTab = index
            }

            Item { Layout.fillWidth: true }
        }

        // 4. Tab Views
        // OVERVIEW TAB: Two columns with bordered segmented rows
        GridLayout {
            visible: detailRoot.activeTab === 0
            opacity: detailRoot.activeTab === 0 ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutQuad } }
            Layout.fillWidth: true
            columns: width >= 420 ? 2 : 1
            columnSpacing: Theme.spacingM
            rowSpacing: Theme.spacingM

            // Left Segmented Group
            Column {
                Layout.fillWidth: true
                spacing: 1

                readonly property var leftItems: [
                    { label: I18n.tr("CPU time"), val: (detailRoot.processData.cpu || 0).toFixed(1) + "%" },
                    { label: I18n.tr("Running for"), val: "Active" },
                    { label: I18n.tr("Threads"), val: detailRoot.procThreads },
                    { label: I18n.tr("Open files"), val: detailRoot.procOpenFiles }
                ]

                Repeater {
                    model: parent.leftItems

                    Rectangle {
                        required property var modelData
                        required property int index

                        width: parent.width
                        height: Theme.buttonHeightXS || 28
                        radius: 4
                        topLeftRadius: index === 0 ? (Theme.groupedListOuterRadius || 10) : 4
                        topRightRadius: index === 0 ? (Theme.groupedListOuterRadius || 10) : 4
                        bottomLeftRadius: index === (parent.leftItems.length - 1) ? (Theme.groupedListOuterRadius || 10) : 4
                        bottomRightRadius: index === (parent.leftItems.length - 1) ? (Theme.groupedListOuterRadius || 10) : 4

                        color: Theme.surfaceContainerHighest || Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.08)
                        border.width: 1
                        border.color: Theme.outlineMedium || Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.12)

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.spacingM
                            anchors.rightMargin: Theme.spacingM

                            StyledText {
                                text: modelData.label
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                                Layout.fillWidth: true
                            }

                            StyledText {
                                text: String(modelData.val)
                                font.pixelSize: Theme.fontSizeSmall
                                font.weight: Font.Medium
                                color: Theme.surfaceText
                            }
                        }
                    }
                }
            }

            // Right Segmented Group
            Column {
                Layout.fillWidth: true
                spacing: 1

                readonly property var rightItems: [
                    { label: I18n.tr("Memory"), val: detailRoot.procMemoryBytes || (`${detailRoot.processData.vram || 0} ${detailRoot.processData.vramUnit || 'MiB'}`) },
                    { label: I18n.tr("Read total"), val: detailRoot.procReadTotal },
                    { label: I18n.tr("Written total"), val: detailRoot.procWriteTotal },
                    { label: I18n.tr("Connections"), val: "0" }
                ]

                Repeater {
                    model: parent.rightItems

                    Rectangle {
                        required property var modelData
                        required property int index

                        width: parent.width
                        height: Theme.buttonHeightXS || 28
                        radius: 4
                        topLeftRadius: index === 0 ? (Theme.groupedListOuterRadius || 10) : 4
                        topRightRadius: index === 0 ? (Theme.groupedListOuterRadius || 10) : 4
                        bottomLeftRadius: index === (parent.rightItems.length - 1) ? (Theme.groupedListOuterRadius || 10) : 4
                        bottomRightRadius: index === (parent.rightItems.length - 1) ? (Theme.groupedListOuterRadius || 10) : 4

                        color: Theme.surfaceContainerHighest || Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.08)
                        border.width: 1
                        border.color: Theme.outlineMedium || Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.12)

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.spacingM
                            anchors.rightMargin: Theme.spacingM

                            StyledText {
                                text: modelData.label
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                                Layout.fillWidth: true
                            }

                            StyledText {
                                text: String(modelData.val)
                                font.pixelSize: Theme.fontSizeSmall
                                font.weight: Font.Medium
                                color: Theme.surfaceText
                            }
                        }
                    }
                }
            }
        }

        // RESOURCES TAB
        GridLayout {
            visible: detailRoot.activeTab === 1
            opacity: detailRoot.activeTab === 1 ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutQuad } }
            Layout.fillWidth: true
            columns: width >= 420 ? 2 : 1
            columnSpacing: Theme.spacingM
            rowSpacing: Theme.spacingM

            Column {
                Layout.fillWidth: true
                spacing: 1

                readonly property var resLeft: [
                    { label: I18n.tr("GPU Engine (GFX)"), val: (detailRoot.processData.gfx || 0) + "%" },
                    { label: I18n.tr("GPU Video"), val: "0%" },
                    { label: I18n.tr("VRAM Dedicated"), val: `${detailRoot.processData.vram || 0} ${detailRoot.processData.vramUnit || 'MiB'}` },
                    { label: I18n.tr("Shared GTT Memory"), val: "—" }
                ]

                Repeater {
                    model: parent.resLeft

                    Rectangle {
                        required property var modelData
                        required property int index

                        width: parent.width
                        height: Theme.buttonHeightXS || 28
                        radius: 4
                        topLeftRadius: index === 0 ? (Theme.groupedListOuterRadius || 10) : 4
                        topRightRadius: index === 0 ? (Theme.groupedListOuterRadius || 10) : 4
                        bottomLeftRadius: index === (parent.resLeft.length - 1) ? (Theme.groupedListOuterRadius || 10) : 4
                        bottomRightRadius: index === (parent.resLeft.length - 1) ? (Theme.groupedListOuterRadius || 10) : 4

                        color: Theme.surfaceContainerHighest || Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.08)
                        border.width: 1
                        border.color: Theme.outlineMedium || Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.12)

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.spacingM
                            anchors.rightMargin: Theme.spacingM

                            StyledText {
                                text: modelData.label
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                                Layout.fillWidth: true
                            }

                            StyledText {
                                text: String(modelData.val)
                                font.pixelSize: Theme.fontSizeSmall
                                font.weight: Font.Medium
                                color: Theme.surfaceText
                            }
                        }
                    }
                }
            }

            Column {
                Layout.fillWidth: true
                spacing: 1

                readonly property var resRight: [
                    { label: I18n.tr("CPU Utilization"), val: (detailRoot.processData.cpu || 0).toFixed(1) + "%" },
                    { label: I18n.tr("System RAM (RSS)"), val: detailRoot.procMemoryBytes || "—" },
                    { label: I18n.tr("Disk Read Rate"), val: detailRoot.procReadTotal },
                    { label: I18n.tr("Disk Write Rate"), val: detailRoot.procWriteTotal }
                ]

                Repeater {
                    model: parent.resRight

                    Rectangle {
                        required property var modelData
                        required property int index

                        width: parent.width
                        height: Theme.buttonHeightXS || 28
                        radius: 4
                        topLeftRadius: index === 0 ? (Theme.groupedListOuterRadius || 10) : 4
                        topRightRadius: index === 0 ? (Theme.groupedListOuterRadius || 10) : 4
                        bottomLeftRadius: index === (parent.resRight.length - 1) ? (Theme.groupedListOuterRadius || 10) : 4
                        bottomRightRadius: index === (parent.resRight.length - 1) ? (Theme.groupedListOuterRadius || 10) : 4

                        color: Theme.surfaceContainerHighest || Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.08)
                        border.width: 1
                        border.color: Theme.outlineMedium || Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.12)

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.spacingM
                            anchors.rightMargin: Theme.spacingM

                            StyledText {
                                text: modelData.label
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                                Layout.fillWidth: true
                            }

                            StyledText {
                                text: String(modelData.val)
                                font.pixelSize: Theme.fontSizeSmall
                                font.weight: Font.Medium
                                color: Theme.surfaceText
                            }
                        }
                    }
                }
            }
        }

        // DETAILS TAB: Full command with copy & system info
        ColumnLayout {
            visible: detailRoot.activeTab === 2
            opacity: detailRoot.activeTab === 2 ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutQuad } }
            Layout.fillWidth: true
            spacing: Theme.spacingS

            Rectangle {
                Layout.fillWidth: true
                Layout.maximumHeight: 180
                implicitHeight: Math.min(180, Math.max(cmdFlickable.contentHeight + Theme.spacingM * 2, copyCmdBtn.height + Theme.spacingS * 2))
                radius: Theme.cornerRadiusM || 8
                color: Theme.surfaceContainerHighest || Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.08)
                border.width: 1
                border.color: Theme.outlineMedium || Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.12)
                clip: true

                Flickable {
                    id: cmdFlickable
                    anchors.left: parent.left
                    anchors.right: copyCmdBtn.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.margins: Theme.spacingS
                    contentWidth: width
                    contentHeight: fullCmdText.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    StyledText {
                        id: fullCmdText
                        width: cmdFlickable.width
                        text: detailRoot.fullCmdline || detailRoot.procName
                        font.pixelSize: Theme.fontSizeSmall
                        font.family: Theme.monoFontFamily || "monospace"
                        color: Theme.surfaceText
                        wrapMode: Text.WrapAnywhere
                    }
                }

                DActionButton {
                    id: copyCmdBtn
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: Theme.spacingS
                    iconName: "content_copy"
                    iconColor: Theme.surfaceText
                    tooltipText: I18n.tr("Copy Full Command")
                    onClicked: Quickshell.execDetached(["dms", "cl", "copy", "--", detailRoot.fullCmdline || detailRoot.procName])
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingM

                Rectangle {
                    Layout.fillWidth: true
                    height: Theme.buttonHeightXS || 28
                    radius: Theme.cornerRadiusS || 6
                    color: Theme.surfaceContainerHighest
                    border.width: 1
                    border.color: Theme.outlineMedium

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: Theme.spacingS
                        StyledText { text: I18n.tr("Parent PID"); font.pixelSize: Theme.fontSizeSmall; color: Theme.surfaceVariantText; Layout.fillWidth: true }
                        StyledText { text: detailRoot.procPPid; font.pixelSize: Theme.fontSizeSmall; color: Theme.surfaceText }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: Theme.buttonHeightXS || 28
                    radius: Theme.cornerRadiusS || 6
                    color: Theme.surfaceContainerHighest
                    border.width: 1
                    border.color: Theme.outlineMedium

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: Theme.spacingS
                        StyledText { text: I18n.tr("State"); font.pixelSize: Theme.fontSizeSmall; color: Theme.surfaceVariantText; Layout.fillWidth: true }
                        StyledText { text: detailRoot.procStatus; font.pixelSize: Theme.fontSizeSmall; color: Theme.surfaceText }
                    }
                }
            }
        }

        // 5. Action Buttons (Priority, Pause/Resume, Restart, Quit/Kill) - Centered
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingS

            Item { Layout.fillWidth: true }

            DButton {
                id: detailPriorityBtn
                text: I18n.tr("Priority")
                iconName: "speed"
                buttonHeight: Theme.buttonHeightXS || 28
                variant: "tonal"
                onClicked: {
                    priorityDropdown.openDropdownMenu();
                }

                DDropdown {
                    id: priorityDropdown
                    showTrigger: false
                    popupAnchorItem: detailPriorityBtn
                    focusReturnTarget: detailPriorityBtn
                    popupWidth: Theme.fontSizeMedium * 10
                    options: ["Highest (-20)", "High (-10)", "Normal (0)", "Low (10)", "Lowest (19)"]
                    optionValues: ["-20", "-10", "0", "10", "19"]
                    onValueChanged: val => {
                        Quickshell.execDetached(["renice", "-n", String(val), "-p", String(detailRoot.pid)]);
                    }
                }
            }

            DButton {
                property bool isPaused: detailRoot.procStatus.startsWith("T")
                text: isPaused ? I18n.tr("Resume") : I18n.tr("Pause")
                iconName: isPaused ? "play_arrow" : "pause"
                buttonHeight: Theme.buttonHeightXS || 28
                variant: "tonal"
                onClicked: {
                    Quickshell.execDetached(["kill", isPaused ? "-CONT" : "-STOP", String(detailRoot.pid)]);
                    isPaused = !isPaused;
                }
            }

            DButton {
                text: I18n.tr("Restart")
                iconName: "restart_alt"
                buttonHeight: Theme.buttonHeightXS || 28
                variant: "tonal"
                onClicked: {
                    if (detailRoot.fullCmdline) {
                        Quickshell.execDetached(["kill", "-9", String(detailRoot.pid)]);
                        Quickshell.execDetached(["sh", "-c", detailRoot.fullCmdline + " &"]);
                    }
                }
            }

            DSplitButton {
                id: quitSplitBtn
                text: I18n.tr("Quit")
                iconName: "close"
                size: "xs"
                variant: "filled"
                onClicked: Quickshell.execDetached(["kill", "-15", String(detailRoot.pid)])
                onMenuClicked: {
                    quitActionDropdown.openDropdownMenu();
                }

                DDropdown {
                    id: quitActionDropdown
                    showTrigger: false
                    popupAnchorItem: quitSplitBtn.trailingButton
                    focusReturnTarget: quitSplitBtn.trailingButton
                    popupWidth: Theme.fontSizeMedium * 12
                    options: [I18n.tr("Force kill (SIGKILL)"), I18n.tr("Terminate tree")]
                    optionValues: ["kill", "tree"]
                    onValueChanged: action => {
                        if (action === "kill") {
                            Quickshell.execDetached(["kill", "-9", String(detailRoot.pid)]);
                        } else {
                            Quickshell.execDetached(["pkill", "-TERM", "-P", String(detailRoot.pid)]);
                            Quickshell.execDetached(["kill", "-TERM", String(detailRoot.pid)]);
                        }
                    }
                }
            }

            Item { Layout.fillWidth: true }
        }
    }
}
