import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import QtQuick.Effects

import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root
    pluginId: "amdGpuMonitorRevive"

    property string variantId: ""
    property var variantData: null

    onPluginDataChanged: {
        if (root.variantId && Array.isArray(pluginData?.variants) && pluginData.variants.length)
            root.variantData = pluginData.variants.find(v => v.id === root.variantId) || root.variantData;
        root.applyStats();
    }

    Connections {
        target: PluginService
        ignoreUnknownSignals: true
        function onGlobalVarChanged(pId, varName) {
            if (pId === root.pluginId) {
                if (root.variantId && Array.isArray(pluginData?.variants) && pluginData.variants.length)
                    root.variantData = pluginData.variants.find(v => v.id === root.variantId) || root.variantData;
                root.applyStats();
            }
        }
    }

    property var contextMenuRef: null
    property real gpuUsage: 0.0
    property real vramUsed: 0.0
    property real vramTotal: 0.0
    property real vramPercent: 0.0
    property int temperature: 0
    property int powerUsage: 0
    property string gpuName: "AMD GPU"
    property var processes: []
    readonly property bool statsError: AmdGpuService.statsError
    property bool gpuSuspended: false

    property real gfxUsage: 0.0
    property real memUsage: 0.0
    property real mediaUsage: 0.0

    function resetStats() {
        if (updateTemperatureFallbackProcess.running)
            updateTemperatureFallbackProcess.running = false;
        temperatureFallbackTimeoutTimer.stop();
        gfxUsage = 0.0;
        memUsage = 0.0;
        mediaUsage = 0.0;
        gpuUsage = 0.0;
        vramUsed = 0.0;
        vramTotal = 0.0;
        vramPercent = 0.0;
        temperature = 0;
        powerUsage = 0;
        temperatureSysfsPath = "";
        processes = [];
    }

    property int updateInterval: Math.max(1000, parseInt(variantData?.updateInterval ?? pluginData?.updateInterval ?? "4000") || 4000)
    property string temperatureSysfsPath: ""
    property var toggleProcessList

    property bool minimumWidth: variantData?.minimumWidth ?? pluginData?.minimumWidth ?? false
    property int gpuIndex: Math.max(0, parseInt(variantData?.gpuIndex ?? "0") || 0)
    property string gpuPci: (variantData?.gpuPci ?? "").toString()
    readonly property string safeGpuPci: (root.gpuPci || "").replace(/[^a-zA-Z0-9_]/g, "_")
    property string popoutStyle: variantData?.popoutStyle ?? pluginData?.popoutStyle ?? "dmsExtended"
    property string processSort: (variantData?.processSort ?? pluginData?.processSort ?? "vram").toString()
    property string widgetDisplayMode: (variantData?.widgetDisplayMode ?? pluginData?.widgetDisplayMode ?? "all").toString()
    readonly property bool isGpuDisabled: {
        if (root.gpuPci) {
            if (pluginData?.[`gpuEnabled_${root.safeGpuPci}`] !== undefined)
                return !pluginData[`gpuEnabled_${root.safeGpuPci}`];
            if (pluginData?.[`gpuEnabled_${root.gpuPci}`] !== undefined)
                return !pluginData[`gpuEnabled_${root.gpuPci}`];
            if (pluginData?.[`gpuDisabled_${root.safeGpuPci}`] !== undefined)
                return !!pluginData[`gpuDisabled_${root.safeGpuPci}`];
            if (pluginData?.[`gpuDisabled_${root.gpuPci}`] !== undefined)
                return !!pluginData[`gpuDisabled_${root.gpuPci}`];
        }
        if (pluginData?.gpuEnabled !== undefined)
            return !pluginData.gpuEnabled;
        return !!pluginData?.gpuDisabled;
    }
    conditionVisible: !root.isGpuDisabled
    readonly property string customGpuName: {
        if (root.gpuPci) {
            if (pluginData?.[`customGpuName_${root.safeGpuPci}`])
                return pluginData[`customGpuName_${root.safeGpuPci}`].toString().trim();
            if (pluginData?.[`customGpuName_${root.gpuPci}`])
                return pluginData[`customGpuName_${root.gpuPci}`].toString().trim();
        }
        return (pluginData?.customGpuName || "").toString().trim();
    }
    readonly property string effectiveGpuName: customGpuName !== "" ? customGpuName : ((variantData?.name && String(variantData.name)) ? variantData.name : root.gpuName)
    readonly property string cleanGpuName: customGpuName !== "" ? customGpuName : ((variantData?.originalGpuName && String(variantData.originalGpuName)) ? variantData.originalGpuName : (root.gpuName ? root.gpuName.replace(/\s+(Utilization|VRAM|Temp)$/i, "") : "AMD GPU"))
    readonly property string widgetIcon: {
        if (variantData?.icon && String(variantData.icon)) return variantData.icon;
        if (widgetDisplayMode === "temperature") return "thermostat";
        if (widgetDisplayMode === "vram") return "developer_board";
        if (widgetDisplayMode === "utilization") return "speed";
        return "dashboard";
    }
    readonly property string displayName: effectiveGpuName
    readonly property string customHeroIcon: {
        if (root.gpuPci) {
            if (pluginData?.[`customHeroIcon_${root.safeGpuPci}`])
                return pluginData[`customHeroIcon_${root.safeGpuPci}`].toString().trim();
            if (pluginData?.[`customHeroIcon_${root.gpuPci}`])
                return pluginData[`customHeroIcon_${root.gpuPci}`].toString().trim();
        }
        return (pluginData?.customHeroIcon || "").toString().trim();
    }
    readonly property string customHeroIconSize: {
        if (root.gpuPci) {
            if (pluginData?.[`customHeroIconSize_${root.safeGpuPci}`])
                return pluginData[`customHeroIconSize_${root.safeGpuPci}`].toString().trim();
            if (pluginData?.[`customHeroIconSize_${root.gpuPci}`])
                return pluginData[`customHeroIconSize_${root.gpuPci}`].toString().trim();
        }
        return (pluginData?.customHeroIconSize || "46").toString().trim();
    }

    popoutWidth: root.popoutStyle === "dmsExtended" ? 640 : 360

    Component.onCompleted: {
        AmdGpuService.request(root, root.updateInterval);
        if (AmdGpuService.devices.length)
            applyStats();
    }
    Component.onDestruction: AmdGpuService.release(root)

    onUpdateIntervalChanged: AmdGpuService.request(root, root.updateInterval)
    onGpuPciChanged: applyStats()
    onProcessSortChanged: applyStats()

    Connections {
        target: AmdGpuService
        function onDevicesChanged() {
            root.applyStats();
        }
    }

    Timer {
        id: temperatureFallbackTimeoutTimer
        interval: 3000
        running: false
        repeat: false
        onTriggered: {
            if (updateTemperatureFallbackProcess.running)
                updateTemperatureFallbackProcess.running = false;
        }
    }

    Process {
        id: updateTemperatureFallbackProcess
        command: []
        running: false

        onRunningChanged: {
            if (running) {
                temperatureFallbackTimeoutTimer.restart();
            } else {
                temperatureFallbackTimeoutTimer.stop();
            }
        }

        stdout: StdioCollector {
            onStreamFinished: {
                const rawValue = text.trim();
                const milliDegrees = parseInt(rawValue);
                if (!isNaN(milliDegrees) && milliDegrees > 0)
                    root.temperature = Math.round(milliDegrees / 1000);
            }
        }
    }

    function applyStats() {
        const device = root.gpuPci
            ? AmdGpuService.deviceByPci(root.gpuPci)
            : AmdGpuService.deviceByIndex(root.gpuIndex) || AmdGpuService.deviceByIndex(0);

        if (!device) {
            root.gpuSuspended = false;
            root.resetStats();
            root.gpuName = "AMD GPU";
            return;
        }

        if (device.suspended) {
            root.resetStats();
            root.gpuName = device.name;
            root.gpuSuspended = true;
            return;
        }
        root.gpuSuspended = false;

        const selectedGpu = device.stats;
        root.gpuName = device.name;

        try {
            root.gfxUsage = parseFloat(selectedGpu.gpu_activity?.["GFX"]?.value) || 0.0;
            root.memUsage = parseFloat(selectedGpu.gpu_activity?.["Memory"]?.value) || 0.0;
            root.mediaUsage = parseFloat(selectedGpu.gpu_activity?.["MediaEngine"]?.value) || 0.0;
            root.gpuUsage = Math.max(root.gfxUsage, root.memUsage, root.mediaUsage);

            root.vramUsed = parseFloat(selectedGpu["VRAM"]?.["Total VRAM Usage"]?.value) || 0.0;
            root.vramTotal = parseFloat(selectedGpu["VRAM"]?.["Total VRAM"]?.value) || 0.0;
            root.vramPercent = root.vramTotal > 0
                ? (root.vramUsed / root.vramTotal * 100) : 0.0;
            const extractedTemperature = root.extractTemperature(selectedGpu);
            if (extractedTemperature > 0) {
                root.temperature = extractedTemperature;
                root.temperatureSysfsPath = "";
            } else if (!root.refreshTemperatureFromSysfs(selectedGpu)) {
                root.temperature = 0;
            }
            root.powerUsage = parseInt(selectedGpu.Sensors?.["Average Power"]?.value ?? selectedGpu.Sensors?.["Input Power"]?.value) || 0;

            if (selectedGpu.fdinfo) {
                const processList = [];

                Object.keys(selectedGpu.fdinfo).forEach(pid => {
                    const procInfo = selectedGpu.fdinfo[pid];
                    const usage = procInfo.usage?.usage;
                    if (!usage) return;

                    const vram = usage.VRAM?.value || 0;
                    const gfx = usage.GFX?.value || 0;
                    const cpu = usage.CPU?.value || 0;

                    if (vram > 0 || gfx > 0) {
                        processList.push({
                            name: procInfo.name || "Unknown",
                            pid: parseInt(pid),
                            vram: vram,
                            vramUnit: usage.VRAM?.unit || "MiB",
                            gfx: gfx,
                            cpu: cpu,
                            gtt: usage.GTT?.value || 0,
                            compute: usage.Compute?.value || 0
                        });
                    }
                });

                processList.sort(root.compareProcesses);
                if (!root.processListsEqual(root.processes, processList))
                    root.processes = processList;
            } else if (root.processes.length > 0) {
                root.processes = [];
            }
        } catch (e) {
            console.warn(`amdGpuMonitor: error applying stats: ${e}`);
        }
    }

    function processListsEqual(a, b) {
        if (a.length !== b.length)
            return false;
        return JSON.stringify(a) === JSON.stringify(b);
    }

    function compareProcesses(a, b) {
        switch (root.processSort) {
            case "gfx":
                return b.gfx - a.gfx;
            case "name":
                return (a.name || "").localeCompare(b.name || "");
            case "pid":
                return a.pid - b.pid;
            case "vram":
            default:
                return b.vram - a.vram;
        }
    }

    function formatVram() {
        if (root.vramTotal < 1024) {
            return `${root.vramUsed.toFixed(0)}/${root.vramTotal.toFixed(0)} MiB`;
        } else {
            const usedGiB = (root.vramUsed / 1024).toFixed(1);
            const totalGiB = (root.vramTotal / 1024).toFixed(1);
            return `${usedGiB}/${totalGiB} GiB`;
        }
    }

    function extractTemperature(selectedGpu) {
        const edgeTemp = parseInt(selectedGpu?.gpu_metrics?.temperature_edge);
        if (!isNaN(edgeTemp) && edgeTemp > 0)
            return edgeTemp;

        const sensorsEdgeTemp = parseInt(selectedGpu?.Sensors?.["Edge Temperature"]?.value);
        if (!isNaN(sensorsEdgeTemp) && sensorsEdgeTemp > 0)
            return sensorsEdgeTemp;

        const gfxTemp = parseInt(selectedGpu?.gpu_metrics?.temperature_gfx);
        if (!isNaN(gfxTemp) && gfxTemp > 0)
            return Math.round(gfxTemp / 100);

        return 0;
    }

    function normalizeSysfsPath(path) {
        if (typeof path !== "string")
            return "";

        const normalizedPath = path.trim().replace(/\/+$/, "");
        return normalizedPath.startsWith("/sys/") ? normalizedPath : "";
    }

    function normalizePciAddress(address) {
        if (typeof address !== "string")
            return "";

        const normalizedAddress = address.trim();
        return /^[0-9a-fA-F]{4}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}\.[0-7]$/.test(normalizedAddress)
            ? normalizedAddress
            : "";
    }

    function getTemperatureSysfsPath(selectedGpu) {
        const infoDevicePath = selectedGpu?.Info?.DevicePath;
        const nestedDevicePath = selectedGpu?.DevicePath;
        const legacyDevicePath = selectedGpu?.device_path;
        const directPath = root.normalizeSysfsPath(
            (typeof infoDevicePath === "string" ? infoDevicePath : infoDevicePath?.sysfs_path)
            || (typeof nestedDevicePath === "string" ? nestedDevicePath : nestedDevicePath?.sysfs_path)
            || (typeof legacyDevicePath === "string" ? legacyDevicePath : legacyDevicePath?.sysfs_path)
            || selectedGpu?.sysfs_path
        );
        if (directPath)
            return directPath;

        const pciAddress = root.normalizePciAddress(
            infoDevicePath?.pci
            || selectedGpu?.PCI
            || selectedGpu?.pci
        );
        if (pciAddress)
            return `/sys/bus/pci/devices/${pciAddress}`;

        return "";
    }

    function refreshTemperatureFromSysfs(selectedGpu) {
        if (updateTemperatureFallbackProcess.running)
            return true;

        const sysfsPath = root.getTemperatureSysfsPath(selectedGpu);
        root.temperatureSysfsPath = sysfsPath;
        if (!sysfsPath)
            return false;

        updateTemperatureFallbackProcess.command = [
            "find",
            `${sysfsPath}/hwmon`,
            "-mindepth",
            "2",
            "-maxdepth",
            "2",
            "-type",
            "f",
            "-name",
            "temp1_input",
            "-exec",
            "cat",
            "{}",
            ";",
            "-quit"
        ];
        updateTemperatureFallbackProcess.running = true;
        return true;
    }

    function getUsageColor(percent) {
        if (percent > 90) return Theme.tempDanger;
        if (percent > 70) return Theme.tempWarning;
        return Theme.primary;
    }

    readonly property color currentPillTextColor: {
        if (root.widgetDisplayMode === "temperature") {
            if (root.temperature > 85) return Theme.tempDanger;
            if (root.temperature > 70) return Theme.tempWarning;
            return Theme.widgetTextColor;
        } else if (root.widgetDisplayMode === "vram") {
            if (root.vramPercent > 90) return Theme.tempDanger;
            if (root.vramPercent > 70) return Theme.tempWarning;
            return Theme.widgetTextColor;
        } else if (root.widgetDisplayMode === "utilization") {
            if (root.gpuUsage > 90) return Theme.tempDanger;
            if (root.gpuUsage > 70) return Theme.tempWarning;
            return Theme.widgetTextColor;
        } else {
            const maxMetric = Math.max(root.gpuUsage, root.vramPercent);
            if (maxMetric > 90) return Theme.tempDanger;
            if (maxMetric > 70) return Theme.tempWarning;
            return Theme.widgetTextColor;
        }
    }

    readonly property color currentPillIconColor: {
        if (root.statsError) return Theme.error;
        if (root.widgetDisplayMode === "temperature") {
            if (root.temperature > 85) return Theme.tempDanger;
            if (root.temperature > 70) return Theme.tempWarning;
        } else if (root.widgetDisplayMode === "vram") {
            if (root.vramPercent > 90) return Theme.tempDanger;
            if (root.vramPercent > 70) return Theme.tempWarning;
        } else if (root.widgetDisplayMode === "utilization") {
            if (root.gpuUsage > 90) return Theme.tempDanger;
            if (root.gpuUsage > 70) return Theme.tempWarning;
        } else {
            const maxMetric = Math.max(root.gpuUsage, root.vramPercent);
            if (maxMetric > 90) return Theme.tempDanger;
            if (maxMetric > 70) return Theme.tempWarning;
        }
        return Theme.widgetIconColor;
    }

    // Helper to extract fields from /proc/[pid]/status
    function extractProcField(text, fieldName) {
        if (!text) return "";
        const lines = text.split("\n");
        for (let line of lines) {
            if (line.startsWith(fieldName + ":")) {
                return line.split(":")[1].trim();
            }
        }
        return "";
    }

    // Helper to format /proc/[pid]/cmdline (replaces null terminators with spaces)
    function formatCmdline(text) {
        if (!text) return "";
        return text.replace(/\0/g, " ").trim();
    }

    function processCategoryIcon(command) {
        if (!command) return "developer_board";
        const cmd = command.toLowerCase();
        if (cmd.includes("firefox") || cmd.includes("chrome") || cmd.includes("browser") || cmd.includes("chromium") || cmd.includes("brave") || cmd.includes("zen"))
            return "web";
        if (cmd.includes("code") || cmd.includes("editor") || cmd.includes("vim") || cmd.includes("nvim") || cmd.includes("subl") || cmd.includes("zed"))
            return "code";
        if (cmd.includes("terminal") || cmd.includes("bash") || cmd.includes("zsh") || cmd.includes("fish") || cmd.includes("kitty") || cmd.includes("alacritty") || cmd.includes("foot") || cmd.includes("wezterm"))
            return "terminal";
        if (cmd.includes("music") || cmd.includes("audio") || cmd.includes("spotify") || cmd.includes("cider"))
            return "music_note";
        if (cmd.includes("video") || cmd.includes("vlc") || cmd.includes("mpv") || cmd.includes("obs") || cmd.includes("kdenlive"))
            return "play_circle";
        if (cmd.includes("steam") || cmd.includes("gamescope") || cmd.includes("wine") || cmd.includes("proton") || cmd.includes("lutris") || cmd.includes("heroic") || cmd.includes("game"))
            return "sports_esports";
        if (cmd.includes("systemd") || cmd.includes("elogind") || cmd.includes("kernel") || cmd.includes("kthread") || cmd.includes("kworker") || cmd.includes("xwayland") || cmd.includes("wayland") || cmd.includes("niri") || cmd.includes("hyprland") || cmd.includes("kwin"))
            return "settings";
        return "memory";
    }

    horizontalBarPill: Component {
        Item {
            id: horizontalPillContainer
            visible: !root.isGpuDisabled
            implicitWidth: root.isGpuDisabled ? 0 : horizontalRow.implicitWidth
            implicitHeight: root.isGpuDisabled ? 0 : horizontalRow.implicitHeight
            width: implicitWidth
            height: implicitHeight
            clip: true

            Row {
                id: horizontalRow
                visible: !root.isGpuDisabled
                spacing: Theme.spacingXS
                DankIcon { 
                    name: root.widgetIcon
                    size: Theme.barIconSize(root.barThickness, undefined, root.barConfig?.maximizeWidgetIcons, root.barConfig?.iconScale)
                    color: root.currentPillIconColor
                    opacity: root.gpuSuspended ? 0.5 : 1.0
                    anchors.verticalCenter: parent.verticalCenter 
                }
                Item {
                    id: textBox
                    anchors.verticalCenter: parent.verticalCenter
                    implicitWidth: root.minimumWidth ? Math.max(textBaseline.width, gpuTextMeasure.width) : gpuTextMeasure.width
                    implicitHeight: gpuText.implicitHeight
                    width: implicitWidth; height: implicitHeight
                    
                    StyledTextMetrics { 
                        id: textBaseline
                        font.pixelSize: Theme.barTextSize(root.barThickness, root.barConfig?.fontScale, root.barConfig?.maximizeWidgetText)
                        text: {
                            if (root.widgetDisplayMode === "temperature") return "99°C";
                            if (root.widgetDisplayMode === "vram") return "18.8GiB";
                            if (root.widgetDisplayMode === "utilization") return "100%";
                            return "88% | 8.8GiB";
                        }
                    }
                    
                    StyledTextMetrics {
                        id: gpuTextMeasure
                        font.pixelSize: Theme.barTextSize(root.barThickness, root.barConfig?.fontScale, root.barConfig?.maximizeWidgetText)
                        text: gpuText.text
                    }
                    
                    StyledText {
                        id: gpuText; anchors.fill: parent
                        font.pixelSize: Theme.barTextSize(root.barThickness, root.barConfig?.fontScale, root.barConfig?.maximizeWidgetText)
                        color: root.currentPillTextColor
                        text: {
                            if (root.widgetDisplayMode === "temperature") {
                                return root.temperature > 0 ? `${root.temperature}°C` : "N/A";
                            } else if (root.widgetDisplayMode === "vram") {
                                return `${(root.vramUsed / 1024).toFixed(1)}GiB`;
                            } else if (root.widgetDisplayMode === "utilization") {
                                return `${root.gpuUsage.toFixed(0)}%`;
                            } else {
                                return `${root.gpuUsage.toFixed(0)}% | ${(root.vramUsed / 1024).toFixed(1)}GiB`;
                            }
                        }
                        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                        wrapMode: Text.NoWrap
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }

    verticalBarPill: Component {
        Item {
            id: verticalPillContainer
            visible: !root.isGpuDisabled
            implicitWidth: root.isGpuDisabled ? 0 : verticalCol.implicitWidth
            implicitHeight: root.isGpuDisabled ? 0 : verticalCol.implicitHeight
            width: implicitWidth
            height: implicitHeight
            clip: true

            Column {
                id: verticalCol
                visible: !root.isGpuDisabled
                spacing: 1

                DankIcon {
                    name: root.widgetIcon
                    size: Theme.barIconSize(root.barThickness, undefined, root.barConfig?.maximizeWidgetIcons, root.barConfig?.iconScale)
                    color: root.currentPillIconColor
                    opacity: root.gpuSuspended ? 0.5 : 1.0
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                StyledText {
                    text: {
                        if (root.widgetDisplayMode === "temperature") {
                            return root.temperature > 0 ? `${root.temperature}°` : "N/A";
                        } else if (root.widgetDisplayMode === "vram") {
                            return `${(root.vramUsed / 1024).toFixed(1)}G`;
                        } else {
                            return `${root.gpuUsage.toFixed(0)}`;
                        }
                    }
                    font.pixelSize: Theme.barTextSize(root.barThickness, root.barConfig?.fontScale, root.barConfig?.maximizeWidgetText)
                    color: root.currentPillTextColor
                    anchors.horizontalCenter: parent.horizontalCenter
                    wrapMode: Text.NoWrap
                    elide: Text.ElideRight
                }
            }
        }
    }

    // Popout content
    popoutContent: Component {
        PopoutComponent {
            id: popout
            
            Connections {
                target: popout
                function onVisibleChanged() {
                    if (!popout.visible && root.contextMenuRef) {
                        root.contextMenuRef.hide();
                    }
                }
            }

            Item {
                id: popoutContainer
                width: parent.width
                implicitHeight: popoutLoader.item ? popoutLoader.item.implicitHeight : 0

                Loader {
                    id: popoutLoader
                    width: parent.width
                    
                    sourceComponent: {
                        switch (root.popoutStyle) {
                            case "alt": return altStyleContent
                            case "dms": return dmsStyleContent
                            case "legacy": return legacyStyleContent
                            case "dmsExtended": return dmsExtendedStyleContent
                        }
                    }
                }

                DankContextMenu {
                    id: contextMenu
                    Component.onCompleted: root.contextMenuRef = contextMenu
                }

                // Global mouse area to close menu when clicking outside
                MouseArea {
                    anchors.fill: parent
                    enabled: contextMenu.visible
                    onPressed: contextMenu.hide()
                    z: 9998 
                }
            }
        }
    }

    // legacy style component
    Component {
        id: legacyStyleContent

        Column {
            width: parent.width
            spacing: Theme.spacingL

            Row {
                width: parent.width; spacing: 8; height: 24
                DankIcon { name: "memory"; size: 18; color: Theme.primary; anchors.verticalCenter: parent.verticalCenter }
                StyledText { text: root.cleanGpuName; font.pixelSize: Theme.fontSizeLarge; font.bold: true; color: Theme.surfaceText; anchors.verticalCenter: parent.verticalCenter }
            }

            // GPU Usage
            Column {
                width: parent.width
                spacing: Theme.spacingS

                Row {
                    width: parent.width

                    StyledText {
                        width: parent.width - 50
                        text: "GPU Usage"
                        color: Theme.surfaceText
                        font.pixelSize: Theme.fontSizeMedium
                    }

                    StyledText {
                        text: `${root.gpuUsage.toFixed(1)}%`
                        color: Theme.surfaceText
                        font.pixelSize: Theme.fontSizeMedium
                        font.bold: true
                    }
                }

                ProgressBar {
                    width: parent.width
                    barHeight: 12
                    barRadius: Theme.cornerRadius
                    value: root.gpuUsage
                    barColor: root.getUsageColor(root.gpuUsage)
                }
            }

            // VRAM Usage
            Column {
                width: parent.width
                spacing: Theme.spacingS

                Row {
                    width: parent.width

                    StyledText {
                        width: parent.width - 100
                        text: "VRAM Usage"
                        color: Theme.surfaceText
                        font.pixelSize: Theme.fontSizeMedium
                    }

                    StyledText {
                        text: root.formatVram()
                        color: Theme.surfaceText
                        font.pixelSize: Theme.fontSizeMedium
                        font.bold: true
                    }
                }

                ProgressBar {
                    width: parent.width
                    barHeight: 12
                    barRadius: Theme.cornerRadius
                    value: root.vramPercent
                    barColor: root.getUsageColor(root.vramPercent)
                }
            }

            Column {
                visible: root.gfxUsage > 0
                width: parent.width
                spacing: Theme.spacingS

                StyledText {
                    text: "Engine Usage"
                    color: Theme.surfaceText
                    font.pixelSize: Theme.fontSizeMedium
                }

                Row {
                    width: parent.width
                    spacing: Theme.spacingL

                    StyledText {
                        text: `GFX: ${root.gfxUsage.toFixed(0)}%`
                        color: Theme.surfaceVariantText
                        font.pixelSize: Theme.fontSizeSmall
                    }

                    StyledText {
                        text: `MEM: ${root.memUsage.toFixed(0)}%`
                        color: Theme.surfaceVariantText
                        font.pixelSize: Theme.fontSizeSmall
                    }

                    StyledText {
                        text: `Media: ${root.mediaUsage.toFixed(0)}%`
                        color: Theme.surfaceVariantText
                        font.pixelSize: Theme.fontSizeSmall
                    }
                }
            }

            // Temperature & Power
            Row {
                width: parent.width
                spacing: Theme.spacingXL

                Column {
                    visible: root.temperature > 0
                    spacing: Theme.spacingXS

                    StyledText {
                        text: "Temperature"
                        color: Theme.surfaceVariantText
                        font.pixelSize: Theme.fontSizeSmall
                    }

                    StyledText {
                        text: `${root.temperature}°C`
                        color: root.temperature > 80 ? Theme.error : Theme.surfaceText
                        font.pixelSize: Theme.fontSizeLarge
                        font.bold: true
                    }
                }

                Column {
                    visible: root.powerUsage > 0
                    spacing: Theme.spacingXS

                    StyledText {
                        text: "Power"
                        color: Theme.surfaceVariantText
                        font.pixelSize: Theme.fontSizeSmall
                    }

                    StyledText {
                        text: `${root.powerUsage}W`
                        color: Theme.surfaceText
                        font.pixelSize: Theme.fontSizeLarge
                        font.bold: true
                    }
                }
            }

            // Process List
            Column {
                visible: root.processes.length > 0
                width: parent.width
                spacing: Theme.spacingS

                StyledText {
                    text: `GPU Processes (${root.processes.length})`
                    color: Theme.surfaceText
                    font.pixelSize: Theme.fontSizeMedium
                    font.bold: true
                }

                DankListView {
                    width: parent.width
                    height: Math.min(contentHeight, 250)
                    model: root.processes
                    spacing: 1
                    clip: true

                    delegate: Rectangle {
                        width: ListView.view.width
                        height: 50
                        color: Theme.surfaceContainer
                        radius: Theme.cornerRadius

                        ToolTip.text: modelData.name
                        ToolTip.visible: legacyProcMouseArea.containsMouse && legacyNameLabel.implicitWidth > legacyNameLabel.width
                        ToolTip.delay: 400

                        MouseArea {
                            id: legacyProcMouseArea
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
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
                            anchors.margins: Theme.spacingS
                            spacing: Theme.spacingM

                            Column {
                                width: 140
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 2

                                StyledText {
                                    id: legacyNameLabel
                                    width: parent.width
                                    text: modelData.name
                                    color: Theme.surfaceText
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.bold: true
                                    elide: Text.ElideRight
                                }

                                StyledText {
                                    text: `PID: ${modelData.pid}`
                                    color: Theme.surfaceVariantText
                                    font.pixelSize: Theme.fontSizeSmall
                                }
                            }

                            Column {
                                width: 70
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 2

                                StyledText {
                                    text: "VRAM"
                                    color: Theme.surfaceVariantText
                                    font.pixelSize: Theme.fontSizeSmall
                                }

                                StyledText {
                                    text: `${modelData.vram} ${modelData.vramUnit}`
                                    color: Theme.primary
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.bold: true
                                }
                            }

                            Column {
                                visible: modelData.gfx > 0
                                width: 50
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 2

                                StyledText {
                                    text: "GPU"
                                    color: Theme.surfaceVariantText
                                    font.pixelSize: Theme.fontSizeSmall
                                }

                                StyledText {
                                    text: `${modelData.gfx}%`
                                    color: Theme.surfaceText
                                    font.pixelSize: Theme.fontSizeSmall
                                }
                            }

                            Column {
                                visible: modelData.cpu > 0
                                width: 50
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 2

                                StyledText {
                                    text: "CPU"
                                    color: Theme.surfaceVariantText
                                    font.pixelSize: Theme.fontSizeSmall
                                }

                                StyledText {
                                    text: `${modelData.cpu}%`
                                    color: Theme.surfaceText
                                    font.pixelSize: Theme.fontSizeSmall
                                }
                            }
                        }
                    }
                }
            }
        }
    }

 // Alternative style
    Component {
        id: altStyleContent

        Column {
            width: parent.width
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
                    
                    DankIcon { 
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

                        DankIcon {
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

                        DankIcon {
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

                        DankIcon {
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

                        DankIcon {
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

                        DankIcon {
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

                    DankListView {
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

                            DankRipple { id: altRipple; cornerRadius: parent.radius }

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
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: Theme.spacingS

                                        DankIcon {
                                            name: root.processCategoryIcon(modelData.name)
                                            size: Theme.iconSizeSmall
                                            color: Theme.surfaceText
                                            opacity: 0.8
                                            anchors.verticalCenter: parent.verticalCenter
                                        }

                                        Column {
                                            anchors.verticalCenter: parent.verticalCenter

                                            StyledText {
                                                id: altProcNameText
                                                text: modelData.name
                                                font.pixelSize: Theme.fontSizeSmall
                                                font.weight: Font.Medium
                                                color: Theme.surfaceText
                                                elide: Text.ElideRight
                                                width: parent.parent.width - Theme.iconSizeSmall - Theme.spacingS
                                            }
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

                                        DankIcon {
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

                                        DankIcon {
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

                                        DankIcon {
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
    }

    // DMS style (matches ProcessListPopout aesthetic)
    Component {
        id: dmsStyleContent

        Column {
            width: parent.width
            spacing: Theme.spacingM

            // GPU Name Div
            Rectangle {
                width: parent.width
                height: 48
                radius: Theme.cornerRadiusL
                color: Theme.withAlpha(Theme.surfaceContainerHigh, Theme.popupTransparency)
                
                border.width: 1
                border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)

                Row {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.spacingM
                    spacing: Theme.spacingM
                    
                    DankIcon { 
                        name: "memory"
                        size: Theme.iconSizeMedium
                        color: Theme.primary
                        anchors.verticalCenter: parent.verticalCenter 
                    }
                    
                    StyledText { 
                        text: root.cleanGpuName
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: Font.Bold
                        color: Theme.surfaceText
                        anchors.verticalCenter: parent.verticalCenter 
                    }
                }
            }

            // Gauges row
            Item {
                id: gaugeRowHost
                width: parent.width
                height: gaugesRow.height
                readonly property real gaugeSize: Theme.fontSizeMedium * 6.5
                readonly property real gaugePadding: Math.max(6, Math.round(gaugeSize * 0.08))

                Row {
                    id: gaugesRow
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.spacingM

                    Item {
                        width: gaugeRowHost.gaugeSize + gaugeRowHost.gaugePadding * 2
                        height: gaugeRowHost.gaugeSize + gaugeRowHost.gaugePadding * 2

                        CircleGauge {
                            anchors.centerIn: parent
                            width: gaugeRowHost.gaugeSize
                            height: gaugeRowHost.gaugeSize
                            value: root.gpuUsage / 100
                            label: root.gpuUsage.toFixed(0) + "%"
                            sublabel: "GPU"
                            accentColor: root.getUsageColor(root.gpuUsage)
                        }
                    }

                    Item {
                        width: gaugeRowHost.gaugeSize + gaugeRowHost.gaugePadding * 2
                        height: gaugeRowHost.gaugeSize + gaugeRowHost.gaugePadding * 2

                        CircleGauge {
                            anchors.centerIn: parent
                            width: gaugeRowHost.gaugeSize
                            height: gaugeRowHost.gaugeSize
                            value: root.vramPercent / 100
                            label: (root.vramUsed / 1024).toFixed(1) + " GiB"
                            sublabel: "VRAM"
                            detail: root.vramPercent.toFixed(0) + "%"
                            accentColor: root.getUsageColor(root.vramPercent)
                        }
                    }

                    Item {
                        visible: root.temperature > 0
                        width: gaugeRowHost.gaugeSize + gaugeRowHost.gaugePadding * 2
                        height: gaugeRowHost.gaugeSize + gaugeRowHost.gaugePadding * 2

                        CircleGauge {
                            anchors.centerIn: parent
                            width: gaugeRowHost.gaugeSize
                            height: gaugeRowHost.gaugeSize
                            value: Math.min(1, root.temperature / 100)
                            label: root.temperature + "°C"
                            sublabel: "Temp"
                            detail: root.powerUsage > 0 ? (root.powerUsage + "W") : ""
                            accentColor: root.temperature > 85 ? Theme.tempDanger : (root.temperature > 70 ? Theme.tempWarning : Theme.info)
                            detailColor: Theme.surfaceVariantText
                        }
                    }
                }
            }

            // Engine activity section
            Rectangle {
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

                        DankIcon {
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

            // Process list section
            Rectangle {
                width: parent.width
                height: processContent.height + Theme.spacingM * 2
                radius: Theme.cornerRadius
                color: Theme.withAlpha(Theme.surfaceContainerHigh, Theme.popupTransparency)

                border.width: 1
                border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)

                Column {
                    id: processContent
                    anchors.left: parent.left

                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: Theme.spacingM
                    spacing: Theme.spacingS

                    Row {
                        spacing: Theme.spacingS

                        DankIcon {
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

                        DankIcon {
                            visible: !!root.toggleProcessList
                            name: "open_in_new"
                            size: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                            opacity: procHeaderMouse.containsMouse ? 1 : 0.6
                            anchors.verticalCenter: parent.verticalCenter
                            
                            MouseArea {
                                id: procHeaderMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.toggleProcessList()
                            }
                        }
                    }

                    DankListView {
                        width: parent.width
                        height: Math.min(contentHeight, 220)
                        model: root.processes
                        spacing: 2
                        clip: true

                        delegate: Rectangle {
                            id: procStyleDelegate
                            clip: true
                            width: ListView.view.width
                            height: 44
                            radius: Theme.cornerRadius
                            Behavior on height { NumberAnimation { duration: Theme.shortDuration; easing.type: Theme.standardEasing } }
                            color: dmsProcMouseArea.containsMouse
                                ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.06)
                                : "transparent"
                            border.color: dmsProcMouseArea.containsMouse
                                ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.12)
                                : "transparent"
                            border.width: 1

                            ToolTip.text: modelData.name
                            ToolTip.visible: dmsProcMouseArea.containsMouse && dmsProcNameText.implicitWidth > dmsProcNameText.width
                            ToolTip.delay: 400

                            DankRipple { id: dmsRipple; cornerRadius: parent.radius }

                            MouseArea {
                                id: dmsProcMouseArea
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                onPressed: dmsRipple.trigger(mouse.x, mouse.y)
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
                                    id: processNameCell
                                    width: parent.width - vramBadge.width - gfxBadge.width - cpuBadge.width - Theme.spacingS * 3
                                    height: parent.height
                                    clip: true

                                    Row {
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: Theme.spacingS

                                        DankIcon {
                                            id: processNameIcon
                                            name: root.processCategoryIcon(modelData.name)
                                            size: Theme.iconSizeSmall
                                            color: Theme.surfaceText
                                            opacity: 0.8
                                            anchors.verticalCenter: parent.verticalCenter
                                        }

                                        Column {
                                            width: Math.max(0, processNameCell.width - processNameIcon.width - Theme.spacingS)
                                            anchors.verticalCenter: parent.verticalCenter

                                            StyledText {
                                                id: dmsProcNameText
                                                text: modelData.name
                                                font.pixelSize: Theme.fontSizeSmall
                                                font.weight: Font.Medium
                                                color: Theme.surfaceText
                                                elide: Text.ElideRight
                                                width: parent.width
                                            }
                                        }
                                    }
                                }

                                // VRAM badge
                                Rectangle {
                                    id: vramBadge
                                    width: 95
                                    height: 24
                                    radius: Theme.cornerRadius
                                    property real procVramPercent: root.vramTotal > 0 ? ((modelData.vramUnit === "GiB" ? modelData.vram * 1024 : modelData.vram) / root.vramTotal * 100) : 0
                                    color: Theme.withAlpha(root.getUsageColor(procVramPercent), 0.15)
                                    anchors.verticalCenter: parent.verticalCenter

                                    Row {
                                        anchors.centerIn: parent
                                        spacing: Theme.spacingXS

                                        DankIcon {
                                            name: "memory"
                                            size: Theme.fontSizeSmall
                                            color: root.getUsageColor(vramBadge.procVramPercent)
                                            anchors.verticalCenter: parent.verticalCenter
                                        }

                                        StyledText {
                                            text: `${modelData.vram} ${modelData.vramUnit}`
                                            font.pixelSize: Theme.fontSizeSmall
                                            font.weight: Font.Bold
                                            color: root.getUsageColor(vramBadge.procVramPercent)
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                    }
                                }

                                // GFX badge
                                Rectangle {
                                    id: gfxBadge
                                    width: 64
                                    height: 24
                                    radius: Theme.cornerRadius
                                    color: Theme.withAlpha(root.getUsageColor(modelData.gfx), 0.15)
                                    anchors.verticalCenter: parent.verticalCenter

                                    Row {
                                        anchors.centerIn: parent
                                        spacing: Theme.spacingXS

                                        DankIcon {
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

                            }
                        }
                    }
                }
            }
        }
    }


    // ==========================================
    // DMS EXTENDED STYLE (Advanced Dashboard)
    // ==========================================
    Component {
        id: dmsExtendedStyleContent

        Column {
            id: rootColumn
            width: parent.width
            spacing: Theme.spacingL

            // Ensures search grabs focus whenever the dashboard becomes visible
            onVisibleChanged: {
                if (visible) searchInput.forceActiveFocus()
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
                        DankIcon { name: "dashboard"; size: Theme.iconSize; color: Theme.primary; anchors.verticalCenter: parent.verticalCenter }
                        StyledText { text: "Processes"; font.pixelSize: Theme.fontSizeMedium; font.weight: Font.Bold; color: Theme.surfaceText; anchors.verticalCenter: parent.verticalCenter }
                        
                        Item { width: Theme.spacingXS; height: 1 }

                        DankIcon {
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

                    // Native DankButtonGroup
                    DankButtonGroup {
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

                // Search bar
                Item {
                    anchors.left: leftControls.right
                    anchors.leftMargin: Theme.spacingM
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    height: Theme.buttonHeightS

                    DankTextField {
                        id: searchInput
                        anchors.fill: parent
                        leftIconName: "search"
                        leftIconColor: Theme.primary
                        leftIconFocusedColor: Theme.primary
                        
                        placeholderText: "Search processes or PIDs..."
                        onTextChanged: processSection.searchText = text.trim()
                        
                        focus: true
                        Component.onCompleted: searchInput.forceActiveFocus()
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
                            visible: root.customHeroIcon !== ""
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
                            
                            layer.enabled: true
                            layer.effect: MultiEffect {
                                shadowEnabled: true
                                shadowColor: Theme.withAlpha(Theme.shadow || "#000000", 0.45)
                                shadowVerticalOffset: 2
                                shadowHorizontalOffset: 1
                                shadowBlur: 0.4
                            }
                        }
                        
                        DankIcon { 
                            visible: root.customHeroIcon === ""
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
                            DankIcon { name: "developer_board"; size: Theme.fontSizeSmall; color: Theme.surfaceVariantText; anchors.verticalCenter: parent.verticalCenter }
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
                        DankIcon { name: "speed"; size: Theme.fontSizeSmall; color: Theme.surfaceVariantText; anchors.verticalCenter: parent.verticalCenter }
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

                FileView { id: cmdViewExt; path: "/proc/" + processSection.expandedPid + "/cmdline" }
                FileView { id: statViewExt; path: "/proc/" + processSection.expandedPid + "/status" }
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

                    if (orderMatches) {
                        for (let i = 0; i < sortedList.length; i++) {
                            let p = sortedList[i];
                            stableModel.setProperty(i, "gfx", p.gfx);
                            stableModel.setProperty(i, "vram", p.vram);
                            stableModel.setProperty(i, "vramUnit", p.vramUnit);
                            stableModel.setProperty(i, "name", p.name);
                        }
                    } else {
                        stableModel.clear();
                        for (let i = 0; i < sortedList.length; i++) {
                            let p = sortedList[i];
                            stableModel.append({
                                name: p.name,
                                pid: p.pid,
                                vram: p.vram,
                                vramUnit: p.vramUnit,
                                gfx: p.gfx
                            });
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

                                        DankIcon {
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
                    DankListView {
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
                            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.shortDuration; easing.type: Theme.standardEasing }
                            NumberAnimation { property: "y"; from: (processListView.y + 10); duration: Theme.shortDuration; easing.type: Theme.standardEasing }
                        }
                        remove: Transition {
                            NumberAnimation { property: "opacity"; to: 0; duration: Theme.shortDuration; easing.type: Theme.standardEasing }
                        }
                        displaced: Transition {
                            NumberAnimation { properties: "y"; duration: Theme.shortDuration; easing.type: Theme.standardEasing }
                        }

                        delegate: Item {
                            id: procDelegate
                            anchors.left: parent ? parent.left : undefined
                            anchors.right: parent ? parent.right : undefined
                            clip: true
                            readonly property bool isExpanded: processSection.expandedPid === model.pid
                            readonly property bool isSelected: isExpanded
                            property bool hovered: procMouseArea.containsMouse

                            readonly property real baseRowH: Theme.listItemHeight || 48
                            height: isExpanded ? (baseRowH + expandedRect.height + Theme.spacingS) : baseRowH
                            opacity: 1
                            visible: true

                            Behavior on height { NumberAnimation { duration: Theme.shortDuration; easing.type: Theme.standardEasing } }
                            Behavior on opacity { NumberAnimation { duration: Theme.shortDuration; easing.type: Theme.standardEasing } }

                            property bool isFirst: index === 0
                            property bool isLast: index === (processListView.count - 1)
                            readonly property real outerRad: Theme.groupedListOuterRadius || Theme.cornerRadiusL
                            readonly property real innerRad: Theme.groupedListInnerRadius || Theme.cornerRadiusXS

                            Rectangle {
                                id: procRowBg
                                anchors.fill: parent
                                clip: true
                                radius: innerRad
                                topLeftRadius: isFirst ? outerRad : innerRad
                                topRightRadius: isFirst ? outerRad : innerRad
                                bottomLeftRadius: isLast ? outerRad : innerRad
                                bottomRightRadius: isLast ? outerRad : innerRad

                                color: procDelegate.isSelected
                                    ? (Theme.selectedContainer || Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.18))
                                    : (procDelegate.hovered
                                        ? Theme.withAlpha(Theme.surfaceVariant, 0.12)
                                        : (Theme.foregroundColor ? Theme.foregroundColor(Theme.chipSurface) : Qt.rgba(Theme.secondary.r, Theme.secondary.g, Theme.secondary.b, 0.04)))

                                border.width: 1
                                border.color: procDelegate.isSelected
                                    ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.5)
                                    : (procDelegate.hovered ? Theme.withAlpha(Theme.primary, 0.3) : Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15))

                                Behavior on color { ColorAnimation { duration: 150 } }
                                Behavior on border.color { ColorAnimation { duration: 150 } }

                                DankRipple { 
                                    id: extRipple
                                    anchors.fill: parent
                                    cornerRadius: isFirst || isLast ? outerRad : innerRad
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
                                spacing: Theme.spacingS

                                DankIcon {
                                    name: root.processCategoryIcon(model.name)
                                    size: Theme.iconSize
                                    color: procDelegate.isSelected ? (Theme.onSelectedContainer || Theme.primary) : (Theme.onSurface || Theme.surfaceText)
                                }

                                Item {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    height: procDelegate.baseRowH

                                    // When unexpanded: only show one clean title vertically centered
                                    StyledText {
                                        id: procTitleText
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: model.name
                                        font.pixelSize: Theme.fontSizeMedium
                                        font.weight: Font.Medium
                                        color: procDelegate.isSelected ? (Theme.onSelectedContainer || Theme.surfaceText) : (Theme.onSurface || Theme.surfaceText)
                                        elide: Text.ElideRight
                                        maximumLineCount: 1
                                    }
                                }

                                // GPU Stat column
                                StyledText {
                                    Layout.preferredWidth: processSection.gpuColW
                                    text: (model.gfx || 0).toFixed(1) + "%"
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: root.getUsageColor(model.gfx)
                                    horizontalAlignment: Text.AlignRight
                                }

                                // VRAM Stat column
                                StyledText {
                                    Layout.preferredWidth: processSection.vramColW
                                    text: processSection.formatProcessBytes(model.vram, model.vramUnit)
                                    font.pixelSize: Theme.fontSizeSmall
                                    property real procVramPercent: root.vramTotal > 0 ? ((model.vramUnit === "GiB" ? model.vram * 1024 : model.vram) / root.vramTotal * 100) : 0
                                    color: root.getUsageColor(procVramPercent)
                                    horizontalAlignment: Text.AlignRight
                                }

                                // PID column
                                StyledText {
                                    Layout.preferredWidth: processSection.pidColW
                                    text: model.pid.toString()
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.onSurfaceVariant || Theme.surfaceVariantText
                                    horizontalAlignment: Text.AlignRight
                                }
                            }

                            // Details Section (When Row is Expanded)
                            Rectangle {
                                id: expandedRect
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.topMargin: procDelegate.baseRowH
                                anchors.leftMargin: Theme.spacingM
                                anchors.rightMargin: Theme.spacingM
                                height: procDelegate.isExpanded ? (expandedContent.implicitHeight + Theme.spacingS * 2) : 0
                                radius: innerRad
                                color: Theme.withAlpha(Theme.surfaceContainerHighest, 0.5)
                                clip: true
                                visible: procDelegate.isExpanded
                                
                                Behavior on height { NumberAnimation { duration: Theme.shortDuration; easing.type: Theme.standardEasing } }
                                opacity: procDelegate.isExpanded ? 1 : 0
                                Behavior on opacity { NumberAnimation { duration: 150 } }

                                ColumnLayout {
                                    id: expandedContent
                                    anchors.fill: parent
                                    anchors.margins: Theme.spacingS
                                    spacing: Theme.spacingXS

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: Theme.spacingS

                                        StyledText {
                                            Layout.fillWidth: true
                                            text: root.formatCmdline(cmdViewExt.text()) || model.name
                                            font.pixelSize: Theme.fontSizeSmall
                                            font.family: Theme.monoFontFamily || "monospace"
                                            color: Theme.surfaceText
                                            wrapMode: Text.WrapAnywhere
                                        }

                                        Rectangle {
                                            Layout.preferredWidth: Theme.buttonHeightXS || 28
                                            Layout.preferredHeight: Theme.buttonHeightXS || 28
                                            radius: height / 2
                                            color: copyMouseArea.containsMouse ? Theme.withAlpha(Theme.primary, 0.15) : "transparent"

                                            DankIcon {
                                                anchors.centerIn: parent
                                                name: "content_copy"
                                                size: Theme.iconSizeSmall
                                                color: copyMouseArea.containsMouse ? Theme.primary : Theme.surfaceVariantText
                                            }

                                            MouseArea {
                                                id: copyMouseArea
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    try {
                                                        Quickshell.execDetached(["dms", "cl", "copy", root.formatCmdline(cmdViewExt.text()) || model.name]);
                                                    } catch(e) {
                                                        console.log("Clipboard copy failed:", e);
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: {
                                            const ppid = root.extractProcField(statViewExt.text(), "PPid") || "--";
                                            let memPct = "--%";
                                            const vmRss = root.extractProcField(statViewExt.text(), "VmRSS");
                                            if (vmRss) {
                                                const rssKb = parseInt(vmRss.replace(/[^0-9]/g, ""));
                                                const memTotalStr = root.extractProcField(memInfoView.text(), "MemTotal");
                                                const memTotalKb = parseInt(memTotalStr.replace(/[^0-9]/g, ""));
                                                if (!isNaN(rssKb) && !isNaN(memTotalKb) && memTotalKb > 0) {
                                                    memPct = (rssKb / memTotalKb * 100).toFixed(1) + "%";
                                                }
                                            }
                                            return "PPID: " + ppid + " · Memory: " + memPct;
                                        }
                                        font.pixelSize: Theme.fontSizeSmall
                                        color: Theme.surfaceVariantText
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

                        DankIcon { name: "search_off"; size: Theme.iconSizeLarge; color: Theme.surfaceVariantText; anchors.horizontalCenter: parent.horizontalCenter }
                        StyledText { text: "No matching processes"; font.pixelSize: Theme.fontSizeSmall; color: Theme.surfaceVariantText; anchors.horizontalCenter: parent.horizontalCenter }
                    }
                }
            }

        }
    }

    // -----------

    // CircleGauge component (matching ProcessListPopout style)
    component CircleGauge: Item {
        id: gaugeRoot

        property real value: 0
        property string label: ""
        property string sublabel: ""
        property string detail: ""
        property color accentColor: Theme.primary
        property color detailColor: Theme.surfaceVariantText

        readonly property real thickness: Math.max(4, Math.min(width, height) / 15)
        readonly property real glowExtra: thickness * 1.4
        readonly property real arcPadding: ((thickness + glowExtra) / 2) + 1
        readonly property real glowStrokeWidth: thickness + glowExtra
        readonly property real ringRadius: Math.max(0, (Math.min(width, height) / 2) - arcPadding)
        readonly property real canvasOverflow: Math.max(0, (glowStrokeWidth / 2) - arcPadding + 1)

        readonly property real innerDiameter: width - (arcPadding + thickness + glowExtra) * 2
        readonly property real maxTextWidth: innerDiameter * 0.9
        readonly property real baseLabelSize: Math.round(width * 0.18)
        readonly property real labelSize: Math.round(Math.min(baseLabelSize, maxTextWidth / Math.max(1, label.length * 0.65)))
        readonly property real sublabelSize: Math.round(Math.min(width * 0.13, maxTextWidth / Math.max(1, sublabel.length * 0.7)))
        readonly property real detailSize: Math.round(Math.min(width * 0.12, maxTextWidth / Math.max(1, detail.length * 0.65)))

        property real animValue: 0

        onValueChanged: animValue = Math.min(1, Math.max(0, value))

        Behavior on animValue {
            NumberAnimation {
                duration: Theme.mediumDuration
                easing.type: Easing.OutCubic
            }
        }

        Component.onCompleted: animValue = Math.min(1, Math.max(0, value))

        Canvas {
            id: glowCanvas
            anchors.centerIn: parent
            width: gaugeRoot.width + gaugeRoot.canvasOverflow * 2
            height: gaugeRoot.height + gaugeRoot.canvasOverflow * 2
            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();
                const cx = width / 2;
                const cy = height / 2;
                const radius = gaugeRoot.ringRadius;
                const startAngle = -Math.PI * 0.5;
                const endAngle = Math.PI * 1.5;

                ctx.lineCap = "round";

                if (gaugeRoot.animValue > 0) {
                    const prog = startAngle + (endAngle - startAngle) * gaugeRoot.animValue;
                    ctx.beginPath();
                    ctx.arc(cx, cy, radius, startAngle, prog);
                    ctx.strokeStyle = Qt.rgba(gaugeRoot.accentColor.r, gaugeRoot.accentColor.g, gaugeRoot.accentColor.b, 0.2);
                    ctx.lineWidth = gaugeRoot.glowStrokeWidth;
                    ctx.stroke();
                }
            }

            Connections {
                target: gaugeRoot
                function onAnimValueChanged() { glowCanvas.requestPaint(); }
                function onAccentColorChanged() { glowCanvas.requestPaint(); }
                function onWidthChanged() { glowCanvas.requestPaint(); }
                function onHeightChanged() { glowCanvas.requestPaint(); }
            }

            Component.onCompleted: requestPaint()
        }

        Canvas {
            id: arcCanvas
            anchors.centerIn: parent
            width: gaugeRoot.width + gaugeRoot.canvasOverflow * 2
            height: gaugeRoot.height + gaugeRoot.canvasOverflow * 2
            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();
                const cx = width / 2;
                const cy = height / 2;
                const radius = gaugeRoot.ringRadius;
                const startAngle = -Math.PI * 0.5;
                const endAngle = Math.PI * 1.5;

                ctx.lineCap = "round";

                ctx.beginPath();
                ctx.arc(cx, cy, radius, startAngle, endAngle);
                ctx.strokeStyle = Qt.rgba(gaugeRoot.accentColor.r, gaugeRoot.accentColor.g, gaugeRoot.accentColor.b, 0.1);
                ctx.lineWidth = gaugeRoot.thickness;
                ctx.stroke();

                if (gaugeRoot.animValue > 0) {
                    const prog = startAngle + (endAngle - startAngle) * gaugeRoot.animValue;
                    ctx.beginPath();
                    ctx.arc(cx, cy, radius, startAngle, prog);
                    ctx.strokeStyle = gaugeRoot.accentColor;
                    ctx.lineWidth = gaugeRoot.thickness;
                    ctx.stroke();
                }
            }

            Connections {
                target: gaugeRoot
                function onAnimValueChanged() { arcCanvas.requestPaint(); }
                function onAccentColorChanged() { arcCanvas.requestPaint(); }
                function onWidthChanged() { arcCanvas.requestPaint(); }
                function onHeightChanged() { arcCanvas.requestPaint(); }
            }

            Component.onCompleted: requestPaint()
        }

        Column {
            anchors.centerIn: parent
            spacing: 1

            StyledText {
                text: gaugeRoot.label
                font.pixelSize: gaugeRoot.labelSize
                font.weight: Font.Bold
                color: Theme.surfaceText
                anchors.horizontalCenter: parent.horizontalCenter
            }

            StyledText {
                text: gaugeRoot.sublabel
                font.pixelSize: gaugeRoot.sublabelSize
                font.weight: Font.Medium
                color: gaugeRoot.accentColor
                anchors.horizontalCenter: parent.horizontalCenter
            }

            StyledText {
                text: gaugeRoot.detail
                font.pixelSize: gaugeRoot.detailSize
                color: gaugeRoot.detailColor
                anchors.horizontalCenter: parent.horizontalCenter
                visible: gaugeRoot.detail.length > 0
            }
        }
    }

    // Stat card component for alt style
    component StatCard: Rectangle {
        id: statCardRoot
        width: 100
        height: 100
        radius: 16
        color: Theme.surfaceContainerHigh

        readonly property color usageColor: root.getUsageColor(statCardRoot.progressValue)
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

                DankIcon {
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

    component ProgressBar: Item {
        id: progressBarRoot
        height: barHeight

        property real value: 0  // 0-100
        property real barHeight: 12
        property real barRadius: barHeight / 2
        property color barColor: Theme.primary
        property color backgroundColor: Theme.surfaceText

        Rectangle {
            anchors.fill: parent
            color: progressBarRoot.backgroundColor
            radius: progressBarRoot.barRadius

            Rectangle {
                width: parent.width * Math.min(1, progressBarRoot.value / 100)
                height: parent.height
                color: progressBarRoot.barColor
                radius: progressBarRoot.barRadius

                Behavior on width {
                    NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
                }
            }
        }
    }

    // Engine bar component
    component EngineBar: Item {
        id: engineBarRoot
        height: 24

        property string label: ""
        property real value: 0
        property color barColor: Theme.primary

        Row {
            anchors.fill: parent
            spacing: Theme.spacingS

            StyledText {
                width: 50
                text: engineBarRoot.label
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceText
                anchors.verticalCenter: parent.verticalCenter
            }

            Rectangle {
                width: parent.width - 100
                height: 8
                radius: 4
                color: Theme.surfaceContainerHighest
                anchors.verticalCenter: parent.verticalCenter

                Rectangle {
                    width: parent.width * (engineBarRoot.value / 100)
                    height: parent.height
                    radius: 4
                    color: engineBarRoot.barColor

                    Behavior on width {
                        NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
                    }
                }
            }

            StyledText {
                width: 40
                text: `${engineBarRoot.value.toFixed(0)}%`
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
                horizontalAlignment: Text.AlignRight
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    // Context Menu Component (Matching Screenshot & Segmented Design)
    component DankContextMenu: Item {
        id: menuRoot
        visible: false
        width: 210
        height: menuCard.implicitHeight || (column.implicitHeight + Theme.spacingS * 2)
        z: 9999

        property var targetProcess: null
        property bool showPid: true
        FileView { id: menuCmdView; path: targetProcess ? ("/proc/" + targetProcess.pid + "/cmdline") : "" }

        function show(px, py, proc, showPid = true) {
            // Keep menu within parent bounds
            let nx = px;
            let ny = py;
            if (nx + width > parent.width) nx = parent.width - width - 10;
            if (ny + height > parent.height) ny = parent.height - height - 10;
            
            x = nx;
            y = ny;
            targetProcess = proc;
            menuRoot.showPid = showPid;
            visible = true;
        }

        function hide() {
            visible = false;
        }

        // Drop shadow behind menu
        Rectangle {
            id: shadowRect
            anchors.fill: menuCard
            radius: menuCard.radius
            color: Theme.withAlpha(Theme.shadow || "#000000", 0.35)
            layer.enabled: true
            layer.effect: MultiEffect {
                blurEnabled: true
                blur: 0.8
                blurMax: 24
                shadowEnabled: true
                shadowColor: Theme.withAlpha(Theme.shadow || "#000000", 0.5)
                shadowVerticalOffset: 6
                shadowHorizontalOffset: 0
                shadowBlur: 1.0
            }
        }

        Rectangle {
            id: menuCard
            anchors.fill: parent
            color: Theme.withAlpha(Theme.surfaceContainerHighest, Theme.popupTransparency || 0.75)
            radius: Theme.cornerRadiusL || 12
            border.color: Theme.outlineMedium || Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)
            border.width: Theme.layerOutlineWidth || 1

            Column {
                id: column
                anchors.fill: parent
                anchors.margins: Theme.spacingS
                spacing: Theme.groupedListGap || 2

                // Header Pill: App Title & Icon
                Rectangle {
                    id: appHeaderPill
                    width: parent.width
                    height: 42
                    clip: true
                    radius: Theme.groupedListOuterRadius || Theme.cornerRadiusL || 12
                    color: Theme.selectedContainer || Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.14)
                    border.width: Theme.layerOutlineWidth || 1
                    border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.3)

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.spacingM
                        anchors.rightMargin: Theme.spacingM
                        spacing: Theme.spacingS

                        DankIcon {
                            name: root.processCategoryIcon(menuRoot.targetProcess ? menuRoot.targetProcess.name : "")
                            size: Theme.iconSizeSmall || 18
                            color: Theme.primary
                            Layout.alignment: Qt.AlignVCenter
                        }

                        StyledText {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            text: menuRoot.targetProcess ? menuRoot.targetProcess.name : "Process"
                            font.pixelSize: Theme.fontSizeMedium
                            font.weight: Font.Bold
                            color: Theme.surfaceText
                            elide: Text.ElideRight
                            maximumLineCount: 1
                        }
                    }
                }

                Item { width: parent.width; height: Theme.spacingXS }

                // Segment 1: PID (if enabled)
                ContextMenuItem {
                    visible: menuRoot.showPid
                    height: menuRoot.showPid ? 38 : 0
                    icon: "tag"; text: "Copy PID"
                    isFirst: true; isLast: true
                    onClicked: {
                        Quickshell.execDetached(["dms", "cl", "copy", menuRoot.targetProcess.pid.toString()]);
                        menuRoot.hide();
                    }
                }

                Item { visible: menuRoot.showPid; width: parent.width; height: Theme.spacingXS }

                // Segment 2: Copy Name & Copy Full Command
                ContextMenuItem {
                    icon: "content_copy"; text: "Copy Name"
                    isFirst: true; isLast: false
                    onClicked: {
                        Quickshell.execDetached(["dms", "cl", "copy", menuRoot.targetProcess.name]);
                        menuRoot.hide();
                    }
                }
                ContextMenuItem {
                    icon: "code"; text: "Copy Full Command"
                    isFirst: false; isLast: true
                    onClicked: {
                        let cmd = root.formatCmdline(menuCmdView.text()) || menuRoot.targetProcess.name;
                        Quickshell.execDetached(["dms", "cl", "copy", cmd]);
                        menuRoot.hide();
                    }
                }

                Item { width: parent.width; height: Theme.spacingXS }

                // Segment 3: Kill Actions
                ContextMenuItem {
                    icon: "close"; text: "Kill Process"
                    isFirst: true; isLast: false
                    hoverColor: Theme.withAlpha(Theme.error, 0.15)
                    hoverIconColor: Theme.error
                    hoverTextColor: Theme.error
                    onClicked: {
                        Quickshell.execDetached(["kill", menuRoot.targetProcess.pid.toString()]);
                        menuRoot.hide();
                    }
                }
                ContextMenuItem {
                    icon: "cancel"; text: "Force Kill (SIGKILL)"
                    isFirst: false; isLast: true
                    hoverColor: Theme.withAlpha(Theme.error, 0.15)
                    hoverIconColor: Theme.error
                    hoverTextColor: Theme.error
                    onClicked: {
                        Quickshell.execDetached(["kill", "-9", menuRoot.targetProcess.pid.toString()]);
                        menuRoot.hide();
                    }
                }
            }
        }
    }

    component ContextMenuItem: Rectangle {
        id: itemRoot
        width: parent.width
        height: 38
        clip: true

        property bool isFirst: false
        property bool isLast: false
        readonly property real outerRad: Theme.groupedListOuterRadius || Theme.cornerRadiusL || 12
        readonly property real innerRad: Theme.groupedListInnerRadius || Theme.cornerRadiusXS || 4

        radius: innerRad
        topLeftRadius: isFirst ? outerRad : innerRad
        topRightRadius: isFirst ? outerRad : innerRad
        bottomLeftRadius: isLast ? outerRad : innerRad
        bottomRightRadius: isLast ? outerRad : innerRad

        Behavior on topLeftRadius { NumberAnimation { duration: 150 } }
        Behavior on topRightRadius { NumberAnimation { duration: 150 } }
        Behavior on bottomLeftRadius { NumberAnimation { duration: 150 } }
        Behavior on bottomRightRadius { NumberAnimation { duration: 150 } }

        color: itemMouseArea.containsMouse
            ? hoverColor
            : (Theme.foregroundColor ? Theme.foregroundColor(Theme.chipSurface) : Qt.rgba(Theme.secondary.r, Theme.secondary.g, Theme.secondary.b, 0.04))

        border.width: Theme.layerOutlineWidth || 1
        border.color: itemMouseArea.containsMouse
            ? Theme.withAlpha(hoverIconColor, 0.35)
            : (Theme.outlineMedium || Qt.rgba(Theme.secondary.r, Theme.secondary.g, Theme.secondary.b, 0.15))

        Behavior on color { ColorAnimation { duration: 150 } }
        Behavior on border.color { ColorAnimation { duration: 150 } }

        property color hoverColor: Theme.withAlpha(Theme.primary, 0.12)
        property color hoverIconColor: Theme.primary
        property color hoverTextColor: Theme.surfaceText

        property string icon: ""
        property string text: ""
        signal clicked()

        DankRipple { id: ripple; cornerRadius: itemRoot.innerRad }

        Row {
            anchors.fill: parent
            anchors.leftMargin: Theme.spacingM
            spacing: Theme.spacingS

            DankIcon {
                name: itemRoot.icon
                size: Theme.iconSizeSmall
                color: itemMouseArea.containsMouse ? itemRoot.hoverIconColor : Theme.surfaceVariantText
                anchors.verticalCenter: parent.verticalCenter
                Behavior on color { ColorAnimation { duration: Theme.shortDuration } }
            }

            StyledText {
                text: itemRoot.text
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Font.Medium
                color: itemMouseArea.containsMouse ? itemRoot.hoverTextColor : Theme.surfaceText
                anchors.verticalCenter: parent.verticalCenter
                Behavior on color { ColorAnimation { duration: Theme.shortDuration } }
            }
        }

        MouseArea {
            id: itemMouseArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onPressed: ripple.trigger(mouse.x, mouse.y)
            onClicked: itemRoot.clicked()
        }
    }
}
