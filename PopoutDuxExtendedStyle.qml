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
    id: rootColumn
    property var root: null
    width: parent ? parent.width : (root ? root.popoutWidth : 640)
    spacing: Theme.spacingL

    function focusSearch() {
        Qt.callLater(() => {
            searchInput.forceActiveFocus();
        });
    }

    // Ensures search grabs focus whenever the dashboard becomes visible
    onVisibleChanged: {
        if (visible) {
            focusSearch();
        }
    }
    Component.onCompleted: {
        focusSearch();
    }

    // Capture typing whenever popout or child items have focus but search input doesn't
    Keys.forwardTo: [searchInput]
    Keys.onPressed: event => {
        if (root && root.contextMenuRef && root.contextMenuRef.visible) return;
        if (event.key === Qt.Key_Escape) {
            if (searchInput.text.length > 0) {
                searchInput.text = "";
                event.accepted = true;
                return;
            }
        }
        if (!searchInput.inputFocused && event.text && event.text.length > 0 && event.key !== Qt.Key_Return && event.key !== Qt.Key_Enter && event.key !== Qt.Key_Tab && event.key !== Qt.Key_Backtab) {
            searchInput.forceActiveFocus();
            searchInput.insertText(event.text);
            event.accepted = true;
        }
    }

            // 1. TOP HEADER: TITLE, FILTER PILLS, SEARCH BAR
            Item {
                width: parent.width
                height: Theme.buttonHeightS

                Row {
                    id: leftControls
                    height: parent.height
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.spacingM

                    Row {
                        height: parent.height
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.spacingS
                        DIcon { name: "dashboard"; size: Theme.iconSize; color: Theme.primary; anchors.verticalCenter: parent.verticalCenter }
                        StyledText { text: "Processes"; font.pixelSize: Theme.fontSizeMedium; font.weight: Font.Bold; color: Theme.surfaceText; anchors.verticalCenter: parent.verticalCenter }
                        
                        Item { width: Theme.spacingXS; height: 1 }

                        DIcon {
                            visible: !!root.toggleProcessList
                            name: "open_in_new"
                            size: Theme.iconSizeMedium
                            color: Theme.primary
                            opacity: extendedProcHeaderMouse.containsMouse ? 1 : 0.6
                            anchors.verticalCenter: parent.verticalCenter
                            
                            MouseArea {
                                id: extendedProcHeaderMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.toggleProcessList()
                            }
                        }
                    }

                    // Native DButtonGroup
                    DButtonGroup {
                        id: processFilters
                        anchors.verticalCenter: parent.verticalCenter
                        buttonHeight: Theme.buttonHeightXS
                        size: "small"
                        checkEnabled: false 
                        model: ["All", "User", "System"]
                        currentIndex: 0
                        onSelectionChanged: function(index, selected) {
                            if (selected) {
                                processFilters.currentIndex = index;
                                processSection.filterMode = index;
                            }
                        }
                    }
                }

                // Search bar (Pill-shaped search field using Theme styling)
                Rectangle {
                    id: searchPillBox
                    anchors.left: leftControls.right
                    anchors.leftMargin: Theme.spacingM
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    height: Theme.buttonHeightS
                    radius: height / 2
                    color: Theme.chipSurface || "#2a282f"
                    border.color: (searchInput && searchInput.inputFocused) ? Theme.primary : (Theme.outlineVariant || "#49454f")
                    border.width: (searchInput && searchInput.inputFocused) ? 2 : 1
                    clip: true

                    DSearchField {
                        id: searchInput
                        anchors.fill: parent
                        backgroundColor: "transparent"
                        borderWidth: 0
                        focusedBorderWidth: 0
                        cornerRadius: searchPillBox.radius
                        radius: searchPillBox.radius
                        leftIconColor: Theme.primary
                        leftIconFocusedColor: Theme.primary
                        showClearButton: true
                        
                        placeholderText: "Search processes or PIDs..."
                        onTextChanged: processSection.searchText = text.trim()
                        
                        focus: true
                        Component.onCompleted: Qt.callLater(() => searchInput.forceActiveFocus())
                    }
                }
            }

            // 2. HERO CARD & GAUGES
            Item {
                width: parent.width
                height: 90 
                
                Row {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.spacingL
                    
                    Rectangle {
                        width: 70; height: 70; radius: 16 
                        color: Theme.withAlpha(Theme.primary, 0.15) 

                        Image {
                            id: customHeroImage
                            visible: !!(root && root.customHeroIcon)
                            anchors.fill: parent
                            anchors.margins: {
                                const size = parseInt(root.customHeroIconSize) || 46;
                                return Math.max(0, (70 - size) / 2);
                            }
                            sourceSize: Qt.size(140, 140) 
                            source: root.customHeroIcon ? (root.customHeroIcon.startsWith("http") || root.customHeroIcon.startsWith("file://") ? root.customHeroIcon : "file://" + root.customHeroIcon) : ""
                            fillMode: Image.PreserveAspectFit
                            mipmap: true
                            asynchronous: true
                            
                            // subtle drop shadow on hero image
                            layer.enabled: false
                        }
                        
                        DIcon { 
                            visible: !(root && root.customHeroIcon)
                            name: "developer_board"
                            size: 34
                            anchors.centerIn: parent
                            color: Theme.primary 
                        }
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        StyledText { text: "GPU"; font.pixelSize: Theme.fontSizeXLarge; font.weight: Font.Bold; color: Theme.surfaceText } 
                        StyledText { text: root.cleanGpuName; font.pixelSize: Theme.fontSizeSmall; color: Theme.surfaceVariantText }
                        Row {
                            spacing: Theme.spacingS
                            DIcon { name: "developer_board"; size: Theme.fontSizeSmall; color: Theme.surfaceVariantText; anchors.verticalCenter: parent.verticalCenter }
                            StyledText { text: root.processes.length + " procs"; font.pixelSize: Theme.fontSizeSmall; color: Theme.surfaceVariantText; anchors.verticalCenter: parent.verticalCenter }
                        }
                    }
                }

                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.spacingL 
                    
                    CircleGauge { 
                        width: 80; height: 80 
                        value: root.gpuUsage / 100
                        label: root.gpuUsage.toFixed(0) + "%"
                        sublabel: "GPU"
                        accentColor: root.getUsageColor(root.gpuUsage) 
                    }
                    
                    CircleGauge { 
                        width: 80; height: 80 
                        value: root.vramPercent / 100
                        label: (root.vramUsed / 1024).toFixed(1) + " GB"
                        sublabel: "Memory"
                        accentColor: root.getUsageColor(root.vramPercent) 
                    }

                    CircleGauge { 
                        visible: root.temperature > 0
                        width: 80; height: 80 
                        value: Math.min(1, root.temperature / 100)
                        label: root.temperature + "°C"
                        sublabel: "Temp"
                        detail: root.powerUsage > 0 ? (root.powerUsage + "W") : ""
                        accentColor: root.temperature > 85 ? Theme.tempDanger : (root.temperature > 70 ? Theme.tempWarning : Theme.info)
                    }
                }
            }

            // 3. ENGINE ACTIVITY SECTION
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
                        DIcon { name: "speed"; size: Theme.fontSizeSmall; color: Theme.surfaceVariantText; anchors.verticalCenter: parent.verticalCenter }
                        StyledText { text: "Engine Activity"; font.pixelSize: Theme.fontSizeSmall; font.weight: Font.Medium; color: Theme.surfaceVariantText; anchors.verticalCenter: parent.verticalCenter }
                    }

                    EngineBar { width: parent.width; label: "GFX"; value: root.gfxUsage; barColor: Theme.primary }
                    EngineBar { width: parent.width; label: "MEM"; value: root.memUsage; barColor: Theme.secondary }
                    EngineBar { width: parent.width; label: "Media"; value: root.mediaUsage; barColor: Theme.info }
                }
            }

            // 4. PROCESS LIST SECTION
            Rectangle {
                id: processSection
                width: parent.width
                height: 380 
                radius: Theme.cornerRadiusL
                color: Theme.withAlpha(Theme.surfaceContainerHighest, Theme.popupTransparency)
                
                border.width: 1
                border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.18)

                FileView { id: cmdViewExt; path: processSection.expandedPid > 0 ? ("/proc/" + processSection.expandedPid + "/cmdline") : "" }
                FileView { id: statViewExt; path: processSection.expandedPid > 0 ? ("/proc/" + processSection.expandedPid + "/status") : "" }
                FileView { id: memInfoView; path: "/proc/meminfo" }

                readonly property real gpuColW: Math.round(Theme.fontSizeSmall * 6.5)
                readonly property real vramColW: Math.round(Theme.fontSizeSmall * 7.5)
                readonly property real pidColW: Math.round(Theme.fontSizeSmall * 5.5)

                function formatProcessBytes(val, unit) {
                    let mib = unit === "GiB" ? (val * 1024) : val;
                    if (mib < 1) return (mib * 1024).toFixed(0) + "K";
                    if (mib < 1000) return mib.toFixed(1) + "M";
                    return (mib / 1024).toFixed(1) + "G";
                }

                property string sortCol: {
                    if (root.processSort === "gfx") return "gpu";
                    if (root.processSort === "vram") return "vram";
                    if (root.processSort === "pid") return "pid";
                    return "name";
                }
                property bool sortAsc: {
                    if (root.processSort === "gfx" || root.processSort === "vram") return false;
                    return true;
                }
                property string searchText: ""
                property int filterMode: 0 
                property int matchCount: 0
                property int expandedPid: -1
                property int detailActiveTab: 0

                signal triggerRecalc()

                Connections {
                    target: root
                    function onProcessSortChanged() {
                        if (root.processSort === "gfx") {
                            processSection.sortCol = "gpu";
                            processSection.sortAsc = false;
                        } else if (root.processSort === "vram") {
                            processSection.sortCol = "vram";
                            processSection.sortAsc = false;
                        } else if (root.processSort === "pid") {
                            processSection.sortCol = "pid";
                            processSection.sortAsc = true;
                        } else {
                            processSection.sortCol = "name";
                            processSection.sortAsc = true;
                        }
                    }
                }

                onSortColChanged: syncData()
                onSortAscChanged: syncData()
                onFilterModeChanged: syncData()
                onSearchTextChanged: syncData()

                ListModel { id: stableModel }

                function sortProcesses(pList) {
                    if (!pList) return [];
                    return pList.sort((a, b) => {
                        let valA, valB;
                        if (processSection.sortCol === "name") {
                            valA = a.name.toLowerCase();
                            valB = b.name.toLowerCase();
                        } else if (processSection.sortCol === "gpu") {
                            valA = a.gfx;
                            valB = b.gfx;
                        } else if (processSection.sortCol === "vram") {
                            valA = a.vram * (a.vramUnit === "GiB" ? 1024 : 1);
                            valB = b.vram * (b.vramUnit === "GiB" ? 1024 : 1);
                        } else if (processSection.sortCol === "pid") {
                            valA = a.pid;
                            valB = b.pid;
                        }

                        let res = 0;
                        if (valA < valB) res = -1;
                        else if (valA > valB) res = 1;
                        
                        return processSection.sortAsc ? res : -res;
                    });
                }

                function syncData() {
                    let rawList = root.processes || [];
                    
                    // 1. FILTER & SEARCH
                    let systemProcs = ["xorg", "xwayland", "wayland", "kwin", "kwin_wayland", "kwin_x11", "niri", "hyprland", "plasmashell", "sddm", "gdm", "systemd"];
                    let filteredList = rawList.filter(p => {
                        let isSys = systemProcs.some(sys => p.name.toLowerCase().includes(sys));
                        let mFilter = processSection.filterMode === 0 || (processSection.filterMode === 1 && !isSys) || (processSection.filterMode === 2 && isSys);
                        let mSearch = processSection.searchText === "" || p.name.toLowerCase().includes(processSection.searchText.toLowerCase()) || p.pid.toString().includes(processSection.searchText);
                        return mFilter && mSearch;
                    });

                    // 2. SORT
                    let sortedList = sortProcesses(filteredList);
                    processSection.matchCount = sortedList.length;

                    // 3. EFFICIENT SYNC (Update in-place or rebuild cleanly without jumping)
                    let pids = sortedList.map(p => p.pid);
                    let currPids = [];
                    for (let i = 0; i < stableModel.count; i++) {
                        currPids.push(stableModel.get(i).pid);
                    }

                    // Check if order changed
                    let orderMatches = (pids.length === currPids.length) && pids.every((pid, idx) => pid === currPids[idx]);

                    // When a process is expanded, do not re-sort/reorder delegates on periodic stats refresh to prevent jumpiness & tab reset
                    if (processSection.expandedPid !== -1) {
                        let existingMap = {};
                        for (let i = 0; i < stableModel.count; i++) {
                            existingMap[stableModel.get(i).pid] = i;
                        }
                        for (let i = 0; i < sortedList.length; i++) {
                            let p = sortedList[i];
                            if (existingMap[p.pid] !== undefined) {
                                let idx = existingMap[p.pid];
                                stableModel.setProperty(idx, "gfx", p.gfx);
                                stableModel.setProperty(idx, "vram", p.vram);
                                stableModel.setProperty(idx, "vramUnit", p.vramUnit);
                                stableModel.setProperty(idx, "name", p.name);
                            }
                        }
                        return;
                    }

                    if (orderMatches) {
                        for (let i = 0; i < sortedList.length; i++) {
                            let p = sortedList[i];
                            stableModel.setProperty(i, "gfx", p.gfx);
                            stableModel.setProperty(i, "vram", p.vram);
                            stableModel.setProperty(i, "vramUnit", p.vramUnit);
                            stableModel.setProperty(i, "name", p.name);
                        }
                    } else {
                        // Reconcile list in-place if PIDs are mostly the same to avoid destroying active delegates
                        let pMap = {};
                        sortedList.forEach(p => { pMap[p.pid] = p; });

                        // Remove items no longer present
                        for (let i = stableModel.count - 1; i >= 0; i--) {
                            if (!pMap[stableModel.get(i).pid]) {
                                stableModel.remove(i);
                            }
                        }

                        // Reorder and update existing, or append new
                        for (let i = 0; i < sortedList.length; i++) {
                            let p = sortedList[i];
                            let foundIdx = -1;
                            for (let j = i; j < stableModel.count; j++) {
                                if (stableModel.get(j).pid === p.pid) {
                                    foundIdx = j;
                                    break;
                                }
                            }
                            if (foundIdx === i) {
                                stableModel.setProperty(i, "gfx", p.gfx);
                                stableModel.setProperty(i, "vram", p.vram);
                                stableModel.setProperty(i, "vramUnit", p.vramUnit);
                                stableModel.setProperty(i, "name", p.name);
                            } else if (foundIdx > i) {
                                stableModel.move(foundIdx, i, 1);
                                stableModel.setProperty(i, "gfx", p.gfx);
                                stableModel.setProperty(i, "vram", p.vram);
                                stableModel.setProperty(i, "vramUnit", p.vramUnit);
                                stableModel.setProperty(i, "name", p.name);
                            } else {
                                stableModel.insert(i, {
                                    name: p.name,
                                    pid: p.pid,
                                    vram: p.vram,
                                    vramUnit: p.vramUnit,
                                    gfx: p.gfx
                                });
                            }
                        }
                    }
                }

                Connections {
                    target: root
                    function onProcessesChanged() { processSection.syncData(); }
                }
                Component.onCompleted: processSection.syncData()

                Item {
                    anchors.fill: parent
                    anchors.margins: Theme.spacingS

                    // TABLE HEADER WITH SORT CHIPS (Arrow integrated inside the active chip)
                    Row {
                        id: tableHeader 
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        height: Theme.buttonHeightS
                        spacing: Theme.groupedListGap || 2
                        z: 10

                        readonly property var sortDefs: [
                            { key: "name", label: "Name" },
                            { key: "gpu", label: "GPU" },
                            { key: "vram", label: "Memory" },
                            { key: "pid", label: "PID" }
                        ]

                        Repeater {
                            model: tableHeader.sortDefs
                            Item {
                                width: (tableHeader.width - (tableHeader.spacing * 3)) / 4
                                height: tableHeader.height

                                readonly property bool isSelected: processSection.sortCol === modelData.key
                                property bool hovered: sortChipMouse.containsMouse
                                readonly property bool isFirst: index === 0
                                readonly property bool isLast: index === (tableHeader.sortDefs.length - 1)

                                readonly property real outerRad: Theme.groupedListOuterRadius || Theme.cornerRadiusL || 12
                                readonly property real innerRad: Theme.groupedListInnerRadius || Theme.cornerRadiusXS || 4
                                readonly property real activeRad: Theme.cornerRadiusFull || (height / 2)

                                Rectangle {
                                    id: chipBg
                                    anchors.fill: parent
                                    radius: innerRad
                                    topLeftRadius: parent.isSelected ? parent.activeRad : (parent.isFirst ? parent.outerRad : parent.innerRad)
                                    bottomLeftRadius: parent.isSelected ? parent.activeRad : (parent.isFirst ? parent.outerRad : parent.innerRad)
                                    topRightRadius: parent.isSelected ? parent.activeRad : (parent.isLast ? parent.outerRad : parent.innerRad)
                                    bottomRightRadius: parent.isSelected ? parent.activeRad : (parent.isLast ? parent.outerRad : parent.innerRad)

                                    Behavior on topLeftRadius { NumberAnimation { duration: 150 } }
                                    Behavior on bottomLeftRadius { NumberAnimation { duration: 150 } }
                                    Behavior on topRightRadius { NumberAnimation { duration: 150 } }
                                    Behavior on bottomRightRadius { NumberAnimation { duration: 150 } }

                                    color: parent.isSelected
                                        ? (Theme.secondaryContainer || Theme.buttonBg)
                                        : (parent.hovered
                                            ? Theme.withAlpha(Theme.surfaceVariant, 0.15)
                                            : (Theme.foregroundColor ? Theme.foregroundColor(Theme.chipSurface) : Theme.withAlpha(Theme.surfaceVariant, 0.2)))

                                    border.width: 1
                                    border.color: parent.isSelected
                                        ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.5)
                                        : Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)

                                    Behavior on color { ColorAnimation { duration: 150 } }
                                    Behavior on border.color { ColorAnimation { duration: 150 } }

                                    Row {
                                        anchors.centerIn: parent
                                        spacing: Theme.spacingXS

                                        DIcon {
                                            id: sortIcon
                                            visible: parent.parent.parent.isSelected
                                            name: "arrow_upward"
                                            rotation: processSection.sortAsc ? 0 : 180
                                            Behavior on rotation { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                                            size: Theme.iconSizeSmall
                                            color: Theme.onSecondaryContainer || Theme.buttonText
                                            anchors.verticalCenter: parent.verticalCenter
                                        }

                                        StyledText {
                                            text: modelData.label
                                            font.pixelSize: Theme.fontSizeSmall
                                            font.weight: parent.parent.parent.isSelected ? Font.Bold : Font.Medium
                                            color: parent.parent.parent.isSelected
                                                ? (Theme.onSecondaryContainer || Theme.buttonText)
                                                : (Theme.onSurfaceVariant || Theme.surfaceVariantText)
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                    }
                                }

                                MouseArea {
                                    id: sortChipMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (processSection.sortCol === modelData.key) {
                                            processSection.sortAsc = !processSection.sortAsc;
                                        } else {
                                            processSection.sortCol = modelData.key;
                                            processSection.sortAsc = (modelData.key === "name" || modelData.key === "pid");
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // GLIDING LIST VIEW
                    DListView {
                    fadeEdges: false
                    showScrollBar: true
                        id: processListView
                        anchors.top: tableHeader.bottom
                        anchors.topMargin: Theme.spacingS
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        clip: true
                        model: stableModel
                        spacing: Theme.groupedListGap || 2
                        boundsBehavior: Flickable.StopAtBounds

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

                        delegate: Item {
                            id: procDelegate
                            anchors.left: parent ? parent.left : undefined
                            anchors.right: parent ? parent.right : undefined
                            clip: true
                            readonly property bool isExpanded: processSection.expandedPid === model.pid
                            readonly property bool isSelected: isExpanded
                            property bool hovered: procMouseArea.containsMouse

                            readonly property real baseRowH: isExpanded ? 64 : (Theme.listItemHeight || 48)
                            height: isExpanded ? (baseRowH + extDetailLoader.implicitHeight + Theme.spacingM) : baseRowH
                            opacity: 1
                            visible: true

                            Behavior on height { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                            Behavior on opacity { NumberAnimation { duration: Theme.shortDuration; easing.type: Theme.standardEasing } }

                            property bool isFirst: index === 0
                            property bool isLast: index === (processListView.count - 1)
                            readonly property real outerRad: Theme.groupedListOuterRadius || Theme.cornerRadiusL
                            readonly property real innerRad: Theme.groupedListInnerRadius || Theme.cornerRadiusXS

                            property real tlr: (hovered || isSelected) ? (baseRowH / 2) : (isFirst ? outerRad : innerRad)
                            property real trr: (hovered || isSelected) ? (baseRowH / 2) : (isFirst ? outerRad : innerRad)
                            property real blr: (hovered || isSelected) ? (baseRowH / 2) : (isLast ? outerRad : innerRad)
                            property real brr: (hovered || isSelected) ? (baseRowH / 2) : (isLast ? outerRad : innerRad)

                            property real tlrAnim: tlr; Behavior on tlrAnim { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
                            property real trrAnim: trr; Behavior on trrAnim { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
                            property real blrAnim: blr; Behavior on blrAnim { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
                            property real brrAnim: brr; Behavior on brrAnim { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }

                            Rectangle {
                                id: procRowBg
                                anchors.fill: parent
                                clip: true
                                topLeftRadius: procDelegate.tlrAnim
                                topRightRadius: procDelegate.trrAnim
                                bottomLeftRadius: procDelegate.blrAnim
                                bottomRightRadius: procDelegate.brrAnim

                                color: procDelegate.isSelected
                                    ? (Theme.selectedContainer || Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.18))
                                    : (procDelegate.hovered
                                        ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.1)
                                        : (Theme.foregroundColor ? Theme.foregroundColor(Theme.chipSurface) : Qt.rgba(Theme.secondary.r, Theme.secondary.g, Theme.secondary.b, 0.04)))

                                border.width: 1
                                border.color: procDelegate.isSelected
                                    ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.6)
                                    : (procDelegate.hovered ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.4) : Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15))

                                Behavior on color { ColorAnimation { duration: 150 } }
                                Behavior on border.color { ColorAnimation { duration: 150 } }

                                DRipple { 
                                    id: extRipple
                                    anchors.fill: parent
                                    cornerRadius: procDelegate.tlrAnim
                                    rippleColor: Theme.primary 
                                }
                            }

                            ToolTip.text: model.name
                            ToolTip.visible: procMouseArea.containsMouse && procTitleText.implicitWidth > procTitleText.width
                            ToolTip.delay: 400

                            MouseArea {
                                id: procMouseArea
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                onPressed: (m) => extRipple.trigger(m.x, m.y)
                                onClicked: function(mouse) {
                                    if (mouse.button === Qt.RightButton && root.contextMenuRef) {
                                        let globalPos = mapToItem(root.contextMenuRef.parent, mouse.x, mouse.y);
                                        root.contextMenuRef.show(globalPos.x, globalPos.y, {
                                            pid: model.pid,
                                            name: model.name,
                                            cmdline: root.formatCmdline(cmdViewExt.text()) || model.name
                                        });
                                    } else {
                                        processSection.expandedPid = isExpanded ? -1 : model.pid;
                                    }
                                }
                            }

                            RowLayout {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                height: procDelegate.baseRowH
                                anchors.leftMargin: Theme.spacingM
                                anchors.rightMargin: Theme.spacingM
                                spacing: procDelegate.isExpanded ? Theme.spacingM : Theme.spacingS

                                Behavior on height { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }

                                Rectangle {
                                    id: extAppIconContainer
                                    width: procDelegate.isExpanded ? 46 : 28
                                    height: procDelegate.isExpanded ? 46 : 28
                                    radius: procDelegate.isExpanded ? (Theme.cornerRadiusM || 10) : 7
                                    color: Theme.surfaceContainerHighest || Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.12)
                                    Layout.alignment: Qt.AlignVCenter

                                    Behavior on width { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                                    Behavior on height { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                                    Behavior on radius { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }

                                    readonly property string iconUrl: root.resolveAppIcon(model.name, model.pid)

                                    Image {
                                        id: extRealAppIcon
                                        anchors.fill: parent
                                        anchors.margins: procDelegate.isExpanded ? 4 : 2
                                        source: extAppIconContainer.iconUrl
                                        fillMode: Image.PreserveAspectFit
                                        smooth: true
                                        mipmap: true
                                        asynchronous: true
                                        visible: status === Image.Ready && source !== ""
                                    }

                                    DIcon {
                                        anchors.centerIn: parent
                                        name: root.processCategoryIcon(model.name)
                                        size: procDelegate.isExpanded ? 28 : (Theme.iconSizeSmall || 16)
                                        color: procDelegate.isSelected ? (Theme.onSelectedContainer || Theme.primary) : (Theme.onSurface || Theme.surfaceText)
                                        visible: !extRealAppIcon.visible
                                    }
                                }

                                Item {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    height: procDelegate.baseRowH

                                    StyledText {
                                        id: procTitleText
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: model.name
                                        font.pixelSize: procDelegate.isExpanded ? (Theme.fontSizeLarge || 18) : Theme.fontSizeMedium
                                        font.weight: procDelegate.isExpanded ? Font.Bold : Font.Medium
                                        color: procDelegate.isSelected ? (Theme.onSelectedContainer || Theme.surfaceText) : (Theme.onSurface || Theme.surfaceText)
                                        elide: Text.ElideRight
                                        maximumLineCount: 1

                                        Behavior on font.pixelSize { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                                    }
                                }

                                // GPU Stat column
                                StyledText {
                                    Layout.preferredWidth: procDelegate.isExpanded ? 0 : processSection.gpuColW
                                    opacity: procDelegate.isExpanded ? 0 : 1
                                    visible: opacity > 0
                                    clip: true
                                    text: (model.gfx || 0).toFixed(1) + "%"
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: root.getUsageColor(model.gfx)
                                    horizontalAlignment: Text.AlignRight

                                    Behavior on opacity { NumberAnimation { duration: 200 } }
                                    Behavior on Layout.preferredWidth { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                                }

                                // VRAM Stat column
                                StyledText {
                                    Layout.preferredWidth: procDelegate.isExpanded ? 0 : processSection.vramColW
                                    opacity: procDelegate.isExpanded ? 0 : 1
                                    visible: opacity > 0
                                    clip: true
                                    text: processSection.formatProcessBytes(model.vram, model.vramUnit)
                                    font.pixelSize: Theme.fontSizeSmall
                                    property real procVramPercent: root.vramTotal > 0 ? ((model.vramUnit === "GiB" ? model.vram * 1024 : model.vram) / root.vramTotal * 100) : 0
                                    color: root.getUsageColor(procVramPercent)
                                    horizontalAlignment: Text.AlignRight

                                    Behavior on opacity { NumberAnimation { duration: 200 } }
                                    Behavior on Layout.preferredWidth { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                                }

                                // PID column
                                StyledText {
                                    Layout.preferredWidth: procDelegate.isExpanded ? 0 : processSection.pidColW
                                    opacity: procDelegate.isExpanded ? 0 : 1
                                    visible: opacity > 0
                                    clip: true
                                    text: model.pid.toString()
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.onSurfaceVariant || Theme.surfaceVariantText
                                    horizontalAlignment: Text.AlignRight

                                    Behavior on opacity { NumberAnimation { duration: 200 } }
                                    Behavior on Layout.preferredWidth { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                                }
                            }

                            // Details Section (When Row is Expanded - matching ProcessDetailStrip screenshot)
                            Loader {
                                id: extDetailLoader
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.leftMargin: Theme.spacingM
                                anchors.rightMargin: Theme.spacingM
                                anchors.top: parent.top
                                anchors.topMargin: procDelegate.baseRowH + Theme.spacingXS
                                active: procDelegate.isExpanded
                                visible: procDelegate.isExpanded
                                sourceComponent: DuxProcessDetailView {
                                    root: rootColumn.root
                                    processData: model
                                    showHeader: false
                                    activeTab: processSection.detailActiveTab
                                    onActiveTabChanged: {
                                        if (processSection.detailActiveTab !== activeTab) {
                                            processSection.detailActiveTab = activeTab;
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Empty state
                    Column {
                        anchors.centerIn: parent
                        spacing: Theme.spacingM
                        opacity: processSection.matchCount === 0 ? 1 : 0
                        
                        Behavior on opacity { 
                            NumberAnimation { 
                                duration: processSection.matchCount === 0 ? 150 : 0 
                                easing.type: Easing.InOutQuad 
                            } 
                        }

                        DIcon { name: "search_off"; size: Theme.iconSizeLarge; color: Theme.surfaceVariantText; anchors.horizontalCenter: parent.horizontalCenter }
                        StyledText { text: "No matching processes"; font.pixelSize: Theme.fontSizeSmall; color: Theme.surfaceVariantText; anchors.horizontalCenter: parent.horizontalCenter }
                    }
                }
            }

        }
