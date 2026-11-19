import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import QtQuick.Effects

import qs.Common
import qs.Widgets
import qs.DCommon.Widgets
import qs.Modules.Plugins
import qs.Services

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
    property var gpuUsageHistory: []
    property var vramUsageHistory: []
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
        gpuUsageHistory = [];
        vramUsageHistory = [];
    }

    property int updateInterval: Math.max(1000, parseInt(variantData?.updateInterval ?? pluginData?.updateInterval ?? "4000") || 4000)
    property string temperatureSysfsPath: ""
    property var toggleProcessList

    property bool minimumWidth: variantData?.minimumWidth ?? pluginData?.minimumWidth ?? false
    property int gpuIndex: Math.max(0, parseInt(variantData?.gpuIndex ?? "0") || 0)
    property string gpuPci: (variantData?.gpuPci ?? "").toString()
    readonly property string safeGpuPci: (root.gpuPci || "").replace(/[^a-zA-Z0-9_]/g, "_")
    property string popoutStyle: {
        const val = (variantData?.popoutStyle ?? pluginData?.popoutStyle ?? "dmsExtended").toString();
        if (val === "dux") return "dms";
        if (val === "duxExtended") return "dmsExtended";
        if (val === "legacy") return "dmsExtended";
        return val;
    }
    property string processSort: {
        if (root.widgetDisplayMode === "utilization") return "gfx";
        if (root.widgetDisplayMode === "vram") return "vram";
        return (variantData?.processSort ?? pluginData?.processSort ?? "vram").toString();
    }
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

    popoutWidth: root.popoutStyle === "dmsExtended" ? 640 : (root.popoutStyle === "dms" ? Math.round(Theme.fontSizeMedium * 46) : 380)

    Component.onCompleted: {
        AmdGpuService.request(root, root.updateInterval);
        if (AmdGpuService.devices.length)
            applyStats();
    }
    Component.onDestruction: AmdGpuService.release(root)

    onUpdateIntervalChanged: AmdGpuService.request(root, root.updateInterval)
    onGpuPciChanged: applyStats()
    onProcessSortChanged: applyStats()
    onWidgetDisplayModeChanged: applyStats()

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

            const newGpuHist = (root.gpuUsageHistory || []).concat([root.gpuUsage]);
            root.gpuUsageHistory = newGpuHist.length > 40 ? newGpuHist.slice(newGpuHist.length - 40) : newGpuHist;

            const newVramHist = (root.vramUsageHistory || []).concat([root.vramPercent]);
            root.vramUsageHistory = newVramHist.length > 40 ? newVramHist.slice(newVramHist.length - 40) : newVramHist;
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

    function formatCmdline(text) {
        if (!text) return "";
        return text.replace(/\0/g, " ").trim();
    }

    function processCategoryIcon(command) {
        if (!command) return "memory";
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

    readonly property var _appIconCache: ({})

    function resolveAppIcon(command, pid) {
        if (!command && !pid) return "";
        const cacheKey = (pid ? (pid + ":") : "") + (command || "");
        if (root._appIconCache[cacheKey] !== undefined)
            return root._appIconCache[cacheKey];

        let icon = "";
        try {
            const raw = (command || "").trim();
            const bin = raw.split("/").pop().split(" ")[0].toLowerCase();
            const candidates = [];

            // 1. If PID is available, check compositor window matching to get exact window appId
            if (pid && typeof CompositorService !== "undefined" && CompositorService) {
                const toplevels = CompositorService.sortedToplevels || [];
                for (let i = 0; i < toplevels.length; i++) {
                    const t = toplevels[i];
                    const wPid = CompositorService.windowPid ? CompositorService.windowPid(t) : 0;
                    if (wPid === pid && t?.appId) {
                        candidates.push(t.appId);
                        break;
                    }
                }
            }

            // 2. Check for Chrome PWA appId in command or candidate names
            // e.g. crx_agimnkijcaahngcdmfeangaknmldooml or --app-id=...
            const pwaMatch = raw.match(/--app-id=([a-zA-Z0-9_-]+)/) || raw.match(/crx_([a-zA-Z0-9_-]+)/);
            if (pwaMatch && pwaMatch[1]) {
                const appId = pwaMatch[1];
                candidates.push("chrome-" + appId + "-Default");
                candidates.push("crx_" + appId);
                candidates.push(appId);
            }

            // 3. Add standard binary candidates and flatpak-style reverse-DNS IDs
            if (raw) candidates.push(raw);
            if (bin && !candidates.includes(bin)) candidates.push(bin);

            // Handle truncated or variant names like com.vscodium.co -> com.vscodium.codium-insiders
            if (bin.startsWith("com.") || bin.startsWith("org.") || bin.startsWith("io.")) {
                if (typeof DesktopEntries !== "undefined" && DesktopEntries && DesktopEntries.applications?.values) {
                    const allApps = DesktopEntries.applications.values;
                    for (let j = 0; j < allApps.length; j++) {
                        const appIdStr = allApps[j]?.id || "";
                        if (appIdStr.startsWith(bin)) {
                            candidates.push(appIdStr);
                            break;
                        }
                    }
                }
            }

            const strippedBin = bin.replace(/[\d._-]+$/, "");
            if (strippedBin && !candidates.includes(strippedBin)) candidates.push(strippedBin);

            // 4. Resolve candidate using DesktopEntries and Paths
            for (const cand of candidates) {
                if (!cand) continue;

                // Check DesktopEntries heuristic lookup
                if (typeof DesktopEntries !== "undefined" && DesktopEntries && DesktopEntries.heuristicLookup) {
                    const entry = DesktopEntries.heuristicLookup(cand);
                    if (entry && entry.icon) {
                        if (entry.icon.startsWith("/") || entry.icon.startsWith("file://")) {
                            icon = entry.icon.startsWith("file://") ? entry.icon : ("file://" + entry.icon);
                            break;
                        }
                        if (typeof Paths !== "undefined" && Paths && Paths.themedIconPath) {
                            icon = Paths.themedIconPath(entry.icon);
                        }
                        if (!icon && typeof Quickshell !== "undefined" && Quickshell.iconPath) {
                            icon = Quickshell.iconPath(entry.icon, true);
                        }
                        if (icon) break;
                    }
                }

                if (typeof Paths !== "undefined" && Paths) {
                    if (Paths.getAppIcon) icon = Paths.getAppIcon(cand, null);
                    if (!icon && Paths.resolveIconPath) icon = Paths.resolveIconPath(cand);
                    if (!icon && Paths.themedIconPath) icon = Paths.themedIconPath(cand);
                }
                if (!icon && typeof Quickshell !== "undefined" && Quickshell.iconPath) {
                    icon = Quickshell.iconPath(cand, true);
                }
                if (icon) break;
            }
        } catch (e) {
            icon = "";
        }

        root._appIconCache[cacheKey] = icon || "";
        return icon || "";
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
                DIcon { 
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

                DIcon {
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
                    if (popout.visible) {
                        Qt.callLater(() => {
                            if (popoutLoader.item && typeof popoutLoader.item.focusSearch === "function") {
                                popoutLoader.item.focusSearch();
                            }
                        });
                    } else if (root.contextMenuRef) {
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
                    property var widgetRoot: root

                    sourceComponent: {
                        switch (root.popoutStyle) {
                            case "alt": return altComp
                            case "dms": return duxComp
                            case "dmsExtended":
                            default: return extComp
                        }
                    }

                    onLoaded: {
                        Qt.callLater(() => {
                            if (item && typeof item.focusSearch === "function") {
                                item.focusSearch();
                            }
                        });
                    }

                    Component {
                        id: altComp
                        PopoutAltStyle { root: popoutLoader.widgetRoot }
                    }

                    Component {
                        id: duxComp
                        PopoutDuxStyle { root: popoutLoader.widgetRoot }
                    }

                    Component {
                        id: extComp
                        PopoutDuxExtendedStyle { root: popoutLoader.widgetRoot }
                    }
                }

                DContextMenuCustom {
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

    // Context Menu Component (Matching Screenshot & Segmented Design)
    component DContextMenuCustom: Item {
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
            anchors.topMargin: 4
            radius: menuCard.radius
            color: Theme.withAlpha(Theme.shadow || "#000000", 0.35)
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

                        DIcon {
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

        DRipple { id: ripple; cornerRadius: itemRoot.innerRad }

        Row {
            anchors.fill: parent
            anchors.leftMargin: Theme.spacingM
            spacing: Theme.spacingS

            DIcon {
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
