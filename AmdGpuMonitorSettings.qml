import QtQuick
import QtQuick.Layouts
import Quickshell

import qs.Common
import qs.Widgets
import qs.Modules.Plugins
import qs.Services

PluginSettings {
    id: root
    pluginId: "amdGpuMonitorRevive"

    readonly property real outerR: Theme.cornerRadius || 12
    readonly property real innerR: 4

    function loadValue(key, def) {
        if (typeof PluginService !== "undefined" && PluginService && PluginService.loadPluginData) {
            return PluginService.loadPluginData(root.pluginId, key, def);
        }
        return def;
    }

    property bool isInternalSave: false

    function saveValue(key, val) {
        if (typeof PluginService !== "undefined" && PluginService && PluginService.savePluginData) {
            root.isInternalSave = true;
            try {
                PluginService.savePluginData(root.pluginId, key, val);
                if (PluginService.setGlobalVar) {
                    PluginService.setGlobalVar(root.pluginId, key, val);
                }
            } finally {
                root.isInternalSave = false;
            }
        }
    }

    property bool multiTypeVariantsEnabled: false

    // [{ name, pci, type, suspended }] as reported by amdgpu_top
    property var detectedGpus: []
    property string detectError: ""
    property bool detecting: true

    function refreshMultiTypeVariantsState() {
        var v = root.loadValue("multiTypeVariants", false);
        root.multiTypeVariantsEnabled = (v === true || v === "true");
    }

    function loadSettings() {
        if (layoutGroup) {
            for (var i = 0; i < layoutGroup.children.length; i++) {
                var item = layoutGroup.children[i];
                if (item && item.loadValue)
                    item.loadValue();
            }
        }
        if (gpuCustomizationRepeater) {
            for (var j = 0; j < gpuCustomizationRepeater.count; j++) {
                var card = gpuCustomizationRepeater.itemAt(j);
                if (card && card.loadValue)
                    card.loadValue();
            }
        }
    }

    Connections {
        target: PluginService
        ignoreUnknownSignals: true
        function onPluginDataChanged(pId) {
            if (pId === root.pluginId && !root.isInternalSave) {
                root.refreshMultiTypeVariantsState();
                root.loadSettings();
            }
        }
        function onGlobalVarChanged(pId, varName) {
            if (pId === root.pluginId && !root.isInternalSave) {
                root.refreshMultiTypeVariantsState();
                root.loadSettings();
            }
        }
    }

    function variantDescription(gpu) {
        const kind = gpu.type === "APU" ? "Integrated" : gpu.type === "dGPU" ? "Discrete" : "";
        return kind ? `Monitor your ${kind.toLowerCase()} ${gpu.name}` : `Monitor your ${gpu.name}`;
    }

    // Pre-PCI variants only carry gpuIndex. Adopt them by position so the sync
    // below doesn't duplicate them and orphan the originals.
    function migrateLegacyVariants() {
        const adopted = [];
        const legacy = (variants || []).filter(v => !v.gpuPci && v.gpuIndex !== undefined);
        if (legacy.length === 0)
            return adopted;

        const claimed = (variants || []).map(v => v.gpuPci).filter(pci => pci);
        for (const variant of legacy) {
            const gpu = AmdGpuService.deviceByIndex(variant.gpuIndex);
            if (!gpu || !gpu.pci || claimed.indexOf(gpu.pci) !== -1)
                continue;
            claimed.push(gpu.pci);
            adopted.push(gpu.pci);
            updateVariant(variant.id, {
                gpuPci: gpu.pci,
                gpuType: gpu.type || "",
                description: variantDescription(gpu),
                icon: variant.icon || "dashboard"
            });
        }
        return adopted;
    }

    property bool isSyncingVariants: false

    // Synchronize auto-generated variants when multiTypeVariants is enabled
    function syncVariantsToGpus() {
        if (root.isSyncingVariants)
            return;
        root.isSyncingVariants = true;
        try {
            if (!root.multiTypeVariantsEnabled) {
                // Clean up auto-generated metric variants when multiTypeVariants is toggled off
                const metricModes = ["utilization", "vram", "temperature"];
                const toRemove = (variants || []).filter(v => v && metricModes.indexOf(v.widgetDisplayMode) !== -1);
                for (const v of toRemove) {
                    if (v && v.id) {
                        root.removeVariant(v.id);
                    }
                }
                return;
            }

            const adopted = migrateLegacyVariants();

            for (const gpu of detectedGpus) {
                // Main GPU variant
                const existing = (variants || []).find(v => v.gpuPci === gpu.pci && (!v.widgetDisplayMode || v.widgetDisplayMode === "all"));
                const gpuType = gpu.type || existing?.gpuType || "";
                const custom = !!(existing?.name && existing.originalName && existing.name !== existing.originalName);
                const keepName = custom || adopted.indexOf(gpu.pci) !== -1;
                const name = existing && keepName ? existing.name : gpu.name;
                const icon = existing?.icon ? existing.icon : "dashboard";
                const config = {
                    gpuPci: gpu.pci,
                    gpuType: gpuType,
                    widgetDisplayMode: "all",
                    originalName: gpu.name,
                    originalGpuName: gpu.name,
                    defaultIcon: "dashboard",
                    description: variantDescription({ name: name, type: gpuType }),
                    icon: icon
                };
                if (!existing) {
                    createVariant(gpu.name, config);
                } else if (existing.name !== name
                           || existing.description !== config.description
                           || existing.gpuType !== gpuType
                           || existing.icon !== config.icon
                           || existing.originalName !== config.originalName
                           || existing.originalGpuName !== config.originalGpuName
                           || existing.defaultIcon !== config.defaultIcon) {
                    updateVariant(existing.id, Object.assign({ name: name }, config));
                }

                // Separate metric widgets (utilization, vram, temperature)
                const metricConfigs = [
                    { mode: "utilization", suffix: "Utilization", icon: "speed", desc: "GPU Load" },
                    { mode: "vram", suffix: "VRAM", icon: "developer_board", desc: "VRAM Usage" },
                    { mode: "temperature", suffix: "Temp", icon: "thermostat", desc: "GPU Temperature" }
                ];
                for (const m of metricConfigs) {
                    const existingMetric = (variants || []).find(v => v.gpuPci === gpu.pci && v.widgetDisplayMode === m.mode);
                    const defaultMetricName = `${gpu.name} ${m.suffix}`;
                    const metricCustom = !!(existingMetric?.name && existingMetric.originalName && existingMetric.name !== existingMetric.originalName);
                    const metricName = existingMetric && metricCustom ? existingMetric.name : defaultMetricName;
                    const metricIcon = existingMetric?.icon ? existingMetric.icon : m.icon;
                    const mConfig = {
                        gpuPci: gpu.pci,
                        gpuType: gpuType,
                        widgetDisplayMode: m.mode,
                        originalName: defaultMetricName,
                        originalGpuName: gpu.name,
                        defaultIcon: m.icon,
                        description: `${m.desc} monitor for ${gpu.name}`,
                        icon: metricIcon
                    };
                    if (!existingMetric) {
                        createVariant(defaultMetricName, mConfig);
                    } else if (existingMetric.name !== metricName
                               || existingMetric.description !== mConfig.description
                               || existingMetric.icon !== mConfig.icon
                               || existingMetric.originalGpuName !== mConfig.originalGpuName
                               || existingMetric.defaultIcon !== mConfig.defaultIcon) {
                        updateVariant(existingMetric.id, Object.assign({ name: metricName }, mConfig));
                    }
                }
            }
        } finally {
            root.isSyncingVariants = false;
        }
    }

    onDetectedGpusChanged: syncVariantsToGpus()
    onMultiTypeVariantsEnabledChanged: syncVariantsToGpus()

    function refreshDetectedGpus() {
        const all = AmdGpuService.devices.slice();
        all.sort((a, b) => a.pci.localeCompare(b.pci));
        // Compare PCI lists to prevent assigning a new array reference when hardware devices haven't changed
        const currentPcis = (root.detectedGpus || []).map(g => g.pci).join(",");
        const newPcis = all.map(g => g.pci).join(",");
        if (currentPcis !== newPcis || root.detectedGpus.length !== all.length) {
            root.detectedGpus = all;
        }
        root.detecting = false;
        root.detectError = AmdGpuService.statsError && !all.length
            ? "Could not run amdgpu_top. Is it installed?"
            : all.length ? "" : "No AMD GPUs detected.";
    }

    Component.onCompleted: {
        root.refreshMultiTypeVariantsState();
        AmdGpuService.request(root, 2000);
        if (AmdGpuService.devices.length)
            refreshDetectedGpus();
        syncVariantsToGpus();
    }
    Component.onDestruction: AmdGpuService.release(root)

    Connections {
        target: AmdGpuService
        function onDevicesChanged() {
            root.refreshDetectedGpus();
        }
        function onStatsErrorChanged() {
            root.refreshDetectedGpus();
        }
    }

    // -------------------------------------------------------------------------
    // REUSABLE COMPONENTS (Matching QuickTote / DMS UI Style)
    // -------------------------------------------------------------------------

    component SectionHeader: Row {
        property string title: ""
        property string iconName: ""

        spacing: Theme.spacingXS
        leftPadding: Theme.spacingM

        DankIcon {
            name: iconName
            size: 16
            color: Theme.primary
            anchors.verticalCenter: parent.verticalCenter
        }

        StyledText {
            text: title
            font.pixelSize: Theme.fontSizeSmall
            font.weight: Font.DemiBold
            color: Theme.primary
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    component SettingsToggleItem: Rectangle {
        id: toggleCard
        width: parent.width
        height: 56
        color: Theme.withAlpha(Theme.surfaceContainerHigh, 0.5)
        border.width: 1
        border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.10)

        property string iconName: ""
        property string title: ""
        property string description: ""
        property string settingKey: ""
        property bool defaultValue: false

        property bool isFirst: false
        property bool isLast: false
        property bool isSingle: false

        property alias checked: toggle.checked
        signal toggled(bool checked)

        topLeftRadius: (isFirst || isSingle) ? root.outerR : root.innerR
        topRightRadius: (isFirst || isSingle) ? root.outerR : root.innerR
        bottomLeftRadius: (isLast || isSingle) ? root.outerR : root.innerR
        bottomRightRadius: (isLast || isSingle) ? root.outerR : root.innerR

        function loadValue() {
            if (root) {
                var loaded = root.loadValue(settingKey, defaultValue);
                checked = loaded === true || loaded === "true";
            }
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Theme.spacingM
            anchors.rightMargin: Theme.spacingM
            spacing: Theme.spacingM

            Rectangle {
                width: 32
                height: 32
                radius: 16
                color: toggle.checked ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15) : Qt.rgba(Theme.surfaceContainerHighest.r, Theme.surfaceContainerHighest.g, Theme.surfaceContainerHighest.b, 0.5)
                Layout.alignment: Qt.AlignVCenter
                Behavior on color { ColorAnimation { duration: 150 } }

                DankIcon {
                    name: toggleCard.iconName
                    size: 18
                    color: toggle.checked ? Theme.primary : Theme.surfaceVariantText
                    anchors.centerIn: parent
                    Behavior on color { ColorAnimation { duration: 150 } }
                }
            }

            Column {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 2
                StyledText {
                    text: toggleCard.title
                    font.weight: Font.Medium
                    color: Theme.surfaceText
                }
                StyledText {
                    text: toggleCard.description
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }
            }

            DankToggle {
                id: toggle
                Layout.alignment: Qt.AlignVCenter
                Component.onCompleted: toggleCard.loadValue()
                onToggled: function (newChecked) {
                    root.saveValue(toggleCard.settingKey, newChecked);
                    toggleCard.toggled(newChecked);
                }
            }
        }
    }

    component SettingsSelectItem: Rectangle {
        id: selectCard
        width: parent.width
        height: 56
        color: Theme.withAlpha(Theme.surfaceContainerHigh, 0.5)
        border.width: 1
        border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.10)

        property string iconName: ""
        property string title: ""
        property string description: ""
        property string settingKey: ""
        property var options: []
        property var defaultValue: ""

        property bool isFirst: false
        property bool isLast: false
        property bool isSingle: false

        topLeftRadius: (isFirst || isSingle) ? root.outerR : root.innerR
        topRightRadius: (isFirst || isSingle) ? root.outerR : root.innerR
        bottomLeftRadius: (isLast || isSingle) ? root.outerR : root.innerR
        bottomRightRadius: (isLast || isSingle) ? root.outerR : root.innerR

        function loadValue() {
            dropdown.loadValue();
        }

        readonly property var optionLabels: {
            const labels = [];
            for (let i = 0; i < options.length; i++) {
                labels.push(options[i].label || options[i]);
            }
            return labels;
        }

        readonly property var valueToLabel: {
            const map = {};
            for (let i = 0; i < options.length; i++) {
                const opt = options[i];
                if (typeof opt === 'object') {
                    map[opt.value] = opt.label;
                } else {
                    map[opt] = opt;
                }
            }
            return map;
        }

        readonly property var labelToValue: {
            const map = {};
            for (let i = 0; i < options.length; i++) {
                const opt = options[i];
                if (typeof opt === 'object') {
                    map[opt.label] = opt.value;
                } else {
                    map[opt] = opt;
                }
            }
            return map;
        }

        RowLayout {
            id: selectRow
            anchors.fill: parent
            anchors.leftMargin: Theme.spacingM
            anchors.rightMargin: Theme.spacingM
            spacing: Theme.spacingM

            Rectangle {
                width: 32
                height: 32
                radius: 16
                color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)
                Layout.alignment: Qt.AlignVCenter

                DankIcon {
                    name: selectCard.iconName
                    size: 18
                    color: Theme.primary
                    anchors.centerIn: parent
                }
            }

            Column {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 2
                StyledText {
                    text: selectCard.title
                    font.weight: Font.Medium
                    color: Theme.surfaceText
                }
                StyledText {
                    text: selectCard.description
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }
            }

            DankDropdown {
                id: dropdown
                Layout.alignment: Qt.AlignVCenter
                compactMode: true
                dropdownWidth: 160
                options: selectCard.optionLabels
                currentValue: selectCard.valueToLabel[selectCard.defaultValue] || selectCard.defaultValue

                function loadValue() {
                    var val = root.loadValue(selectCard.settingKey, selectCard.defaultValue);
                    currentValue = selectCard.valueToLabel[val] || val;
                }

                Component.onCompleted: loadValue()

                onValueChanged: function(newLabel) {
                    var actualVal = selectCard.labelToValue[newLabel] !== undefined ? selectCard.labelToValue[newLabel] : newLabel;
                    root.saveValue(selectCard.settingKey, actualVal);
                }
            }
        }
    }

    component SettingsFieldItem: Rectangle {
        id: fieldCard
        width: parent.width
        implicitHeight: fieldCol.implicitHeight + Theme.spacingM * 2
        color: Theme.withAlpha(Theme.surfaceContainerHigh, 0.5)
        border.width: 1
        border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.10)

        property string iconName: ""
        property string title: ""
        property string description: ""
        property string settingKey: ""
        property string defaultValue: ""
        property string placeholderText: ""

        property bool isFirst: false
        property bool isLast: false
        property bool isSingle: false

        topLeftRadius: (isFirst || isSingle) ? root.outerR : root.innerR
        topRightRadius: (isFirst || isSingle) ? root.outerR : root.innerR
        bottomLeftRadius: (isLast || isSingle) ? root.outerR : root.innerR
        bottomRightRadius: (isLast || isSingle) ? root.outerR : root.innerR

        function loadValue() {
            customField.loadValue();
        }

        Column {
            id: fieldCol
            anchors.fill: parent
            anchors.margins: Theme.spacingM
            spacing: Theme.spacingS

            RowLayout {
                width: parent.width
                spacing: Theme.spacingM

                Rectangle {
                    width: 32
                    height: 32
                    radius: 16
                    color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)
                    Layout.alignment: Qt.AlignVCenter

                    DankIcon {
                        name: fieldCard.iconName
                        size: 18
                        color: Theme.primary
                        anchors.centerIn: parent
                    }
                }

                Column {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 2
                    StyledText {
                        text: fieldCard.title
                        font.weight: Font.Medium
                        color: Theme.surfaceText
                    }
                    StyledText {
                        text: fieldCard.description
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }
                }
            }

            DankTextField {
                id: customField
                width: parent.width
                placeholderText: fieldCard.placeholderText !== "" ? fieldCard.placeholderText : fieldCard.defaultValue
                function loadValue() {
                    if (root) {
                        text = root.loadValue(fieldCard.settingKey, fieldCard.defaultValue);
                    }
                }
                Component.onCompleted: loadValue()
                onEditingFinished: {
                    root.saveValue(fieldCard.settingKey, text);
                }
            }
        }
    }

    component SettingsSliderItem: Rectangle {
        id: sliderCard
        width: parent.width
        implicitHeight: sliderInnerCol.implicitHeight + Theme.spacingM * 2
        color: Theme.withAlpha(Theme.surfaceContainerHigh, 0.5)
        border.width: 1
        border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.10)

        property string iconName: ""
        property string title: ""
        property string description: ""
        property string settingKey: ""
        property int defaultValue: 0
        property int minimumValue: 1
        property int maximumValue: 100
        property string unit: "px"
        property bool sliderEnabled: true

        property bool isFirst: false
        property bool isLast: false
        property bool isSingle: false

        topLeftRadius: (isFirst || isSingle) ? root.outerR : root.innerR
        topRightRadius: (isFirst || isSingle) ? root.outerR : root.innerR
        bottomLeftRadius: (isLast || isSingle) ? root.outerR : root.innerR
        bottomRightRadius: (isLast || isSingle) ? root.outerR : root.innerR

        function loadValue() {
            slider.loadValue();
        }

        Column {
            id: sliderInnerCol
            anchors.fill: parent
            anchors.margins: Theme.spacingM
            spacing: Theme.spacingS

            RowLayout {
                width: parent.width
                spacing: Theme.spacingM

                Rectangle {
                    width: 32
                    height: 32
                    radius: 16
                    color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)
                    Layout.alignment: Qt.AlignVCenter

                    DankIcon {
                        name: sliderCard.iconName
                        size: 18
                        color: Theme.primary
                        anchors.centerIn: parent
                    }
                }

                Column {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 2
                    StyledText {
                        text: sliderCard.title
                        font.weight: Font.Medium
                        color: Theme.surfaceText
                    }
                    StyledText {
                        text: sliderCard.description
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }
                }

                Rectangle {
                    id: resetBtn
                    width: 32
                    height: 32
                    radius: 16
                    Layout.alignment: Qt.AlignVCenter
                    color: resetMa.containsMouse ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.1) : Qt.rgba(Theme.secondary.r, Theme.secondary.g, Theme.secondary.b, 0.04)
                    border.color: resetMa.containsMouse ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.4) : Qt.rgba(Theme.secondary.r, Theme.secondary.b, Theme.secondary.b, 0.15)
                    border.width: 1
                    opacity: slider.value !== sliderCard.defaultValue ? (resetMa.containsMouse ? 1.0 : 0.9) : 0.0
                    visible: opacity > 0
                    scale: resetMa.pressed ? 0.9 : (resetMa.containsMouse ? 1.05 : 1.0)

                    Behavior on color { ColorAnimation { duration: 150 } }
                    Behavior on border.color { ColorAnimation { duration: 150 } }
                    Behavior on opacity { NumberAnimation { duration: 150 } }
                    Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }

                    DankRipple { 
                        id: resetRip
                        anchors.fill: parent
                        cornerRadius: parent.radius
                        rippleColor: Theme.primary 
                    }

                    DankIcon {
                        id: resetIcon
                        name: "restart_alt"
                        size: 16
                        anchors.centerIn: parent
                        color: resetMa.containsMouse ? Theme.primary : Theme.surfaceVariantText
                        SequentialAnimation on rotation {
                            running: resetMa.containsMouse; loops: Animation.Infinite
                            NumberAnimation { to: 8; duration: 75 }
                            NumberAnimation { to: -8; duration: 150 }
                            NumberAnimation { to: 0; duration: 75 }
                            onRunningChanged: { if (!running) resetIcon.rotation = 0; }
                        }
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }

                    MouseArea {
                        id: resetMa
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: slider.value !== sliderCard.defaultValue && sliderCard.sliderEnabled
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            resetAnim.restart();
                            root.saveValue(sliderCard.settingKey, sliderCard.defaultValue);
                        }
                        onPressed: (m) => resetRip.trigger(m.x, m.y)
                    }
                }

                NumberAnimation {
                    id: resetAnim
                    target: slider
                    property: "value"
                    to: sliderCard.defaultValue
                    duration: 150
                    easing.type: Easing.OutCubic
                }
            }

            RowLayout {
                width: parent.width
                spacing: Theme.spacingM

                DankSlider {
                    id: slider
                    property string settingKey: sliderCard.settingKey
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    minimum: sliderCard.minimumValue
                    maximum: sliderCard.maximumValue
                    step: 1
                    unit: sliderCard.unit
                    wheelEnabled: false
                    enabled: sliderCard.sliderEnabled

                    function loadValue() {
                        if (root)
                            value = root.loadValue(settingKey, sliderCard.defaultValue);
                    }
                    Component.onCompleted: loadValue()
                    onSliderValueChanged: newValue => {
                        value = newValue;
                        root.saveValue(settingKey, newValue);
                    }
                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.NoButton
                        onWheel: (wheel) => { wheel.accepted = true; }
                    }
                }

                Rectangle {
                    id: smallBox
                    width: 64
                    height: 32
                    color: Theme.surfaceContainerHigh
                    radius: height / 2
                    border.color: textInput.activeFocus ? Theme.primary : Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.20)
                    border.width: 1
                    Layout.alignment: Qt.AlignVCenter
                    opacity: sliderCard.sliderEnabled ? 1.0 : 0.4

                    TextInput {
                        id: textInput
                        anchors.fill: parent
                        anchors.margins: 4
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        color: Theme.surfaceText
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: Font.Medium
                        enabled: sliderCard.sliderEnabled
                        text: activeFocus ? slider.value.toString() : (slider.value + (sliderCard.unit ? sliderCard.unit : ""))
                        selectByMouse: true

                        onEditingFinished: {
                            var cleanText = text.replace(/[^0-9.-]/g, "").trim();
                            var parsed = parseInt(cleanText, 10);
                            if (!isNaN(parsed)) {
                                var clamped = Math.max(sliderCard.minimumValue, Math.min(sliderCard.maximumValue, parsed));
                                slider.value = clamped;
                                root.saveValue(sliderCard.settingKey, clamped);
                            }
                            textInput.focus = false;
                        }

                        onAccepted: {
                            editingFinished();
                        }
                    }
                }
            }
        }
    }

    // -------------------------------------------------------------------------
    // MAIN SETTINGS CONTENT
    // -------------------------------------------------------------------------

    Column {
        id: rootWrapper
        width: parent.width
        spacing: Theme.spacingM

        // General Layout Settings Group
        Column {
            width: parent.width
            spacing: Theme.spacingS

            SectionHeader {
                title: "General & Widget Configuration"
                iconName: "tune"
            }

            Column {
                id: layoutGroup
            width: parent.width
            spacing: 2

            SettingsSelectItem {
                iconName: "dashboard"
                title: "Popout Style"
                description: "Visual style for the popout panel."
                settingKey: "popoutStyle"
                options: [
                    { label: "Legacy", value: "legacy" },
                    { label: "Alternative", value: "alt" },
                    { label: "DMS", value: "dms" },
                    { label: "DMS Extended", value: "dmsExtended" }
                ]
                defaultValue: "dmsExtended"
                isFirst: true
            }

            SettingsToggleItem {
                iconName: "aspect_ratio"
                title: "Force Padding"
                description: "Prevent widget width from changing as values update."
                settingKey: "minimumWidth"
                defaultValue: false
            }

            SettingsSelectItem {
                iconName: "schedule"
                title: "Update Interval"
                description: "How often amdgpu_top is polled."
                settingKey: "updateInterval"
                options: [
                    { label: "1s", value: "1000" },
                    { label: "2s", value: "2000" },
                    { label: "4s", value: "4000" },
                    { label: "8s", value: "8000" },
                    { label: "15s", value: "15000" }
                ]
                defaultValue: "4000"
            }

            SettingsSelectItem {
                iconName: "sort"
                title: "Process List Sort"
                description: "Default sort order for the GPU process list."
                settingKey: "processSort"
                options: [
                    { label: "VRAM Usage", value: "vram" },
                    { label: "GPU Usage (GFX)", value: "gfx" },
                    { label: "Process Name", value: "name" },
                    { label: "PID", value: "pid" }
                ]
                defaultValue: "vram"
            }

            SettingsSelectItem {
                iconName: "visibility"
                title: "Bar Metric Display"
                description: "Metric shown on the Dank Bar widget."
                settingKey: "widgetDisplayMode"
                options: [
                    { label: "All (Utilization & VRAM)", value: "all" },
                    { label: "Utilization Only (%)", value: "utilization" },
                    { label: "VRAM Usage Only", value: "vram" },
                    { label: "Temperature Only (°C)", value: "temperature" }
                ]
                defaultValue: "all"
            }

            SettingsToggleItem {
                iconName: "splitscreen"
                title: "Multi-Type Metric Widgets"
                description: "Generate separate dedicated Dank Bar widgets for each GPU and metric (Utilization, VRAM, and Temperature)."
                settingKey: "multiTypeVariants"
                defaultValue: false
                isLast: true
                onToggled: function (newChecked) {
                    root.multiTypeVariantsEnabled = newChecked;
                    root.syncVariantsToGpus();
                }
            }
        }
    }

    // Dynamic Per-GPU Customization Section
    Column {
        width: parent.width
        spacing: Theme.spacingM

        SectionHeader {
            title: "GPU Hardware & Appearance"
            iconName: "developer_board"
        }

        Repeater {
            id: gpuCustomizationRepeater
            model: root.detectedGpus && root.detectedGpus.length > 0
                   ? root.detectedGpus
                   : [{ pci: "default", name: "AMD GPU" }]

            delegate: Rectangle {
                id: gpuCard
                required property var modelData
                required property int index

                readonly property string safePci: (modelData.pci || "").replace(/[^a-zA-Z0-9_]/g, "_")
                readonly property bool isCustomPci: !!(modelData.pci && modelData.pci !== "default")
                readonly property string nameKey: isCustomPci ? `customGpuName_${safePci}` : "customGpuName"
                readonly property string heroIconKey: isCustomPci ? `customHeroIcon_${safePci}` : "customHeroIcon"
                readonly property string heroIconSizeKey: isCustomPci ? `customHeroIconSize_${safePci}` : "customHeroIconSize"
                readonly property string enabledKey: isCustomPci ? `gpuEnabled_${safePci}` : "gpuEnabled"
                readonly property string legacyDisabledKey: isCustomPci ? `gpuDisabled_${safePci}` : "gpuDisabled"

                property bool isFirst: true
                property bool isLast: true
                property bool isSingle: true

                width: parent.width
                implicitHeight: cardCol.implicitHeight + Theme.spacingM * 2
                color: Theme.withAlpha(Theme.surfaceContainerHigh, 0.5)
                border.width: 1
                border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.10)

                topLeftRadius: root.outerR
                topRightRadius: root.outerR
                bottomLeftRadius: root.outerR
                bottomRightRadius: root.outerR

                function loadValue() {
                    var enabledVal = root.loadValue(gpuCard.enabledKey, undefined);
                    if (enabledVal === undefined) {
                        var disabledVal = root.loadValue(gpuCard.legacyDisabledKey, false);
                        gpuEnabledToggle.checked = !(disabledVal === true || disabledVal === "true");
                    } else {
                        gpuEnabledToggle.checked = enabledVal === true || enabledVal === "true";
                    }
                    gpuNameField.text = root.loadValue(gpuCard.nameKey, "");
                    heroIconField.text = root.loadValue(gpuCard.heroIconKey, "");
                    heroIconSizeSlider.loadValue();
                }

                Column {
                    id: cardCol
                    anchors.fill: parent
                    anchors.margins: Theme.spacingM
                    spacing: Theme.spacingM

                    // Top Row: GPU Title / PCI on left, Enable GPU Toggle on same line on right
                    RowLayout {
                        width: parent.width
                        spacing: Theme.spacingM

                        Rectangle {
                            width: 32
                            height: 32
                            radius: 16
                            color: gpuEnabledToggle.checked ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15) : Qt.rgba(Theme.surfaceContainerHighest.r, Theme.surfaceContainerHighest.g, Theme.surfaceContainerHighest.b, 0.5)
                            Layout.alignment: Qt.AlignVCenter
                            Behavior on color { ColorAnimation { duration: 150 } }

                            DankIcon {
                                name: "developer_board"
                                size: 18
                                color: gpuEnabledToggle.checked ? Theme.primary : Theme.surfaceVariantText
                                anchors.centerIn: parent
                                Behavior on color { ColorAnimation { duration: 150 } }
                            }
                        }

                        Column {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 2
                            StyledText {
                                text: modelData.pci && modelData.pci !== "default"
                                      ? `${modelData.name} (${modelData.pci})`
                                      : (modelData.name || "AMD GPU")
                                font.weight: Font.Bold
                                color: Theme.surfaceText
                            }
                            StyledText {
                                text: gpuEnabledToggle.checked ? "Configure name, icon, and visibility" : "Widget disabled on Dank Bar"
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                            }
                        }

                        Row {
                            Layout.alignment: Qt.AlignVCenter
                            spacing: Theme.spacingXS

                            DankToggle {
                                id: gpuEnabledToggle
                                anchors.verticalCenter: parent.verticalCenter
                                Component.onCompleted: {
                                    var enabledVal = root.loadValue(gpuCard.enabledKey, undefined);
                                    if (enabledVal === undefined) {
                                        var disabledVal = root.loadValue(gpuCard.legacyDisabledKey, false);
                                        checked = !(disabledVal === true || disabledVal === "true");
                                    } else {
                                        checked = enabledVal === true || enabledVal === "true";
                                    }
                                }
                                onToggled: function (newChecked) {
                                    root.saveValue(gpuCard.enabledKey, newChecked);
                                    root.saveValue(gpuCard.legacyDisabledKey, !newChecked);
                                }
                            }
                        }
                    }

                    // Collapsible GPU customization options
                    Item {
                        id: optionsContainer
                        width: parent.width
                        property bool expanded: gpuEnabledToggle.checked
                        implicitHeight: expanded ? optionsCol.implicitHeight : 0
                        clip: true
                        opacity: expanded ? 1.0 : 0.0
                        visible: opacity > 0

                        Behavior on implicitHeight {
                            NumberAnimation {
                                duration: Theme.shortDuration || 200
                                easing.type: Easing.OutCubic
                            }
                        }
                        Behavior on opacity {
                            NumberAnimation {
                                duration: Theme.shortDuration || 200
                            }
                        }

                        Column {
                            id: optionsCol
                            width: parent.width
                            spacing: Theme.spacingM
                            topPadding: Theme.spacingS

                            Rectangle {
                                width: parent.width
                                height: 1
                                color: Theme.outline
                                opacity: 0.15
                            }

                            // Custom GPU Display Name
                            Column {
                                width: parent.width
                                spacing: Theme.spacingXS

                                RowLayout {
                                    width: parent.width
                                    spacing: Theme.spacingM

                                    Rectangle {
                                        width: 28
                                        height: 28
                                        radius: 14
                                        color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)
                                        Layout.alignment: Qt.AlignVCenter

                                        DankIcon {
                                            name: "badge"
                                            size: 16
                                            color: Theme.primary
                                            anchors.centerIn: parent
                                        }
                                    }

                                    Column {
                                        Layout.fillWidth: true
                                        Layout.alignment: Qt.AlignVCenter
                                        spacing: 1
                                        StyledText {
                                            text: "Custom GPU Display Name"
                                            font.weight: Font.Medium
                                            color: Theme.surfaceText
                                        }
                                        StyledText {
                                            text: "Override the GPU name across all UI styles for this GPU."
                                            font.pixelSize: Theme.fontSizeSmall
                                            color: Theme.surfaceVariantText
                                            Layout.fillWidth: true
                                            elide: Text.ElideRight
                                        }
                                    }
                                }

                                DankTextField {
                                    id: gpuNameField
                                    width: parent.width
                                    placeholderText: modelData.name || "e.g. Radeon RX 7900 XTX"
                                    Component.onCompleted: {
                                        text = root.loadValue(gpuCard.nameKey, "");
                                    }
                                    onEditingFinished: {
                                        root.saveValue(gpuCard.nameKey, text);
                                    }
                                }
                            }

                            // Custom Hero Icon Path
                            Column {
                                width: parent.width
                                spacing: Theme.spacingXS

                                RowLayout {
                                    width: parent.width
                                    spacing: Theme.spacingM

                                    Rectangle {
                                        width: 28
                                        height: 28
                                        radius: 14
                                        color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)
                                        Layout.alignment: Qt.AlignVCenter

                                        DankIcon {
                                            name: "image"
                                            size: 16
                                            color: Theme.primary
                                            anchors.centerIn: parent
                                        }
                                    }

                                    Column {
                                        Layout.fillWidth: true
                                        Layout.alignment: Qt.AlignVCenter
                                        spacing: 1
                                        StyledText {
                                            text: "Custom Hero Icon Path"
                                            font.weight: Font.Medium
                                            color: Theme.surfaceText
                                        }
                                        StyledText {
                                            text: "Absolute path or URL to replace the default logo in DMS Extended."
                                            font.pixelSize: Theme.fontSizeSmall
                                            color: Theme.surfaceVariantText
                                            Layout.fillWidth: true
                                            elide: Text.ElideRight
                                        }
                                    }
                                }

                                DankTextField {
                                    id: heroIconField
                                    width: parent.width
                                    placeholderText: "/path/to/icon.png"
                                    Component.onCompleted: {
                                        text = root.loadValue(gpuCard.heroIconKey, "");
                                    }
                                    onEditingFinished: {
                                        root.saveValue(gpuCard.heroIconKey, text);
                                    }
                                }
                            }

                            // Custom Hero Icon Size
                            SettingsSliderItem {
                                id: heroIconSizeSlider
                                iconName: "photo_size_select_large"
                                title: "Custom Icon Size (px)"
                                description: "Width and height of the custom icon (max 70). Default is 46."
                                settingKey: gpuCard.heroIconSizeKey
                                defaultValue: 46
                                minimumValue: 20
                                maximumValue: 70
                                unit: "px"
                                isSingle: true
                            }
                        }
                    }
                }
            }
        }
    }

    Rectangle {
        width: parent.width
        height: 1
        color: Theme.outline
        opacity: 0.3
        visible: root.multiTypeVariantsEnabled
    }

    StyledText {
        width: parent.width
        text: "Your GPUs"
        font.pixelSize: Theme.fontSizeMedium
        font.weight: Font.Medium
        color: Theme.surfaceText
        visible: root.multiTypeVariantsEnabled
    }

    StyledText {
        width: parent.width
        text: "Each detected GPU gets its own widget automatically. Add them from Add Widget in the Dank Bar settings."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
        visible: root.multiTypeVariantsEnabled
    }

    // Detected GPUs segmented list with loading spinner (Revive card styling)
    Column {
        id: detectedGpusContainer
        width: parent.width
        spacing: 2
        visible: root.multiTypeVariantsEnabled

        Rectangle {
            width: parent.width
            height: 56
            visible: root.detecting && root.detectedGpus.length === 0
            radius: root.outerR
            color: Theme.withAlpha(Theme.surfaceContainerHigh, 0.5)
            border.width: 1
            border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.10)

            Row {
                anchors.centerIn: parent
                spacing: Theme.spacingM

                Item {
                    width: 20
                    height: 20
                    anchors.verticalCenter: parent.verticalCenter

                    DankIcon {
                        name: "progress_activity"
                        size: 20
                        color: Theme.surfaceVariantText
                        anchors.centerIn: parent
                    }

                    NumberAnimation on rotation {
                        from: 0
                        to: 360
                        duration: 1000
                        loops: Animation.Infinite
                        running: root.detecting && root.detectedGpus.length === 0
                    }
                }

                StyledText {
                    text: "Detecting GPUs..."
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }

        Repeater {
            id: detectedGpusRepeater
            model: root.detectedGpus

            delegate: Rectangle {
                id: detectedGpuCard
                required property var modelData
                required property int index

                readonly property bool isFirst: index === 0
                readonly property bool isLast: index === (detectedGpusRepeater.count - 1)
                readonly property bool isSingle: detectedGpusRepeater.count === 1

                width: parent.width
                height: 56
                color: Theme.withAlpha(Theme.surfaceContainerHigh, 0.5)
                border.width: 1
                border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.10)

                topLeftRadius: (isFirst || isSingle) ? root.outerR : root.innerR
                topRightRadius: (isFirst || isSingle) ? root.outerR : root.innerR
                bottomLeftRadius: (isLast || isSingle) ? root.outerR : root.innerR
                bottomRightRadius: (isLast || isSingle) ? root.outerR : root.innerR

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.spacingM
                    anchors.rightMargin: Theme.spacingM
                    spacing: Theme.spacingM

                    Rectangle {
                        width: 32
                        height: 32
                        radius: 16
                        color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)
                        Layout.alignment: Qt.AlignVCenter

                        DankIcon {
                            name: "developer_board"
                            size: 18
                            color: Theme.primary
                            anchors.centerIn: parent
                        }
                    }

                    Column {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 2

                        StyledText {
                            text: detectedGpuCard.modelData.name
                            font.weight: Font.Medium
                            color: Theme.surfaceText
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }

                        StyledText {
                            text: detectedGpuCard.modelData.suspended
                                  ? `${detectedGpuCard.modelData.pci} (suspended)`
                                  : (detectedGpuCard.modelData.pci || "")
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }
                    }
                }
            }
        }

        StyledText {
            width: parent.width
            visible: root.detectError !== ""
            text: root.detectError
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.error
            wrapMode: Text.WordWrap
        }
    }

    StyledText {
        width: parent.width
        text: "Configured Widgets"
        font.pixelSize: Theme.fontSizeMedium
        font.weight: Font.Medium
        color: Theme.surfaceText
        visible: root.multiTypeVariantsEnabled
    }

    StyledText {
        width: parent.width
        text: "Widgets currently saved in your settings. You can edit names, change icons, or remove them."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
        visible: root.multiTypeVariantsEnabled
    }

    // Configured widgets list with inline editor (Segmented / Processlist style)
    Column {
        id: variantsListColumn
        width: parent.width
        spacing: 2
        visible: root.multiTypeVariantsEnabled

        Repeater {
            model: root.variantsModel

            Rectangle {
                id: variantEntry

                required property var modelData
                required property int index

                readonly property bool legacy: !variantEntry.modelData.gpuPci || variantEntry.modelData.gpuIndex !== undefined

                property bool editing: false
                property string pendingIcon: ""       // text-field value, empty = use picker
                property string pickerIcon: "dashboard" // last dropdown selection

                property bool isFirst: index === 0
                property bool isLast: index === (root.variantsModel.count - 1)
                property bool isSingle: root.variantsModel.count === 1
                readonly property real outerRad: root.outerR
                readonly property real innerRad: root.innerR

                topLeftRadius: (isFirst || isSingle) ? outerRad : innerRad
                topRightRadius: (isFirst || isSingle) ? outerRad : innerRad
                bottomLeftRadius: (isLast || isSingle) ? outerRad : innerRad
                bottomRightRadius: (isLast || isSingle) ? outerRad : innerRad

                Behavior on topLeftRadius { NumberAnimation { duration: 150 } }
                Behavior on topRightRadius { NumberAnimation { duration: 150 } }
                Behavior on bottomLeftRadius { NumberAnimation { duration: 150 } }
                Behavior on bottomRightRadius { NumberAnimation { duration: 150 } }

                function beginEdit() {
                    editNameField.text = variantEntry.modelData.name;
                    variantEntry.pendingIcon = "";
                    variantEntry.pickerIcon = variantEntry.modelData.icon || "dashboard";
                    iconTextField.text = "";
                    variantEntry.editing = true;
                }

                function commitEdit() {
                    const newName = editNameField.text.trim() || variantEntry.modelData.name;
                    const newIcon = (variantEntry.pendingIcon || variantEntry.pickerIcon || "dashboard").trim();
                    root.updateVariant(variantEntry.modelData.id, {
                        name: newName,
                        icon: newIcon
                    });
                    variantEntry.editing = false;
                }

                width: parent.width
                height: editing ? editorColumn.implicitHeight + Theme.spacingM * 2
                                : displayRow.implicitHeight + Theme.spacingM * 2
                color: Theme.withAlpha(Theme.surfaceContainerHigh, 0.5)
                border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.10)
                border.width: 1
                opacity: 0.8
                scale: 1.0

                Component.onCompleted: {
                    entryAddAnim.start();
                }

                ParallelAnimation {
                    id: entryAddAnim
                    NumberAnimation { target: variantEntry; property: "opacity"; from: 0; to: 0.8; duration: Theme.shortDuration || 200; easing.type: Easing.OutCubic }
                    NumberAnimation { target: variantEntry; property: "scale"; from: 0.96; to: 1.0; duration: Theme.shortDuration || 200; easing.type: Easing.OutBack }
                }

                SequentialAnimation {
                    id: entryDeleteAnim
                    ParallelAnimation {
                        NumberAnimation { target: variantEntry; property: "opacity"; to: 0; duration: Theme.shortDuration || 150; easing.type: Easing.InCubic }
                        NumberAnimation { target: variantEntry; property: "scale"; to: 0.92; duration: Theme.shortDuration || 150; easing.type: Easing.InCubic }
                    }
                    ScriptAction {
                        script: {
                            const variant = variantEntry.modelData;
                            root.removeVariant(variant.id);
                        }
                    }
                }

                Behavior on height {
                    NumberAnimation { duration: Theme.shortDuration || 200; easing.type: Easing.OutCubic }
                }

                Row {
                    id: displayRow
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: Theme.spacingM
                    anchors.rightMargin: Theme.spacingM
                    spacing: Theme.spacingM
                    visible: !variantEntry.editing

                    Rectangle {
                        width: 32
                        height: 32
                        radius: 16
                        color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)
                        anchors.verticalCenter: parent.verticalCenter

                        DankIcon {
                            id: variantIcon
                            name: variantEntry.modelData.icon || "dashboard"
                            size: 18
                            color: Theme.primary
                            anchors.centerIn: parent
                        }
                    }

                    Column {
                        id: variantRow
                        width: parent.width - 32 - buttonGroupRow.width - Theme.spacingM * 2
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2

                        StyledText {
                            width: parent.width
                            text: variantEntry.modelData.name || "Unnamed"
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Font.Medium
                            color: Theme.surfaceText
                            elide: Text.ElideRight
                        }

                        StyledText {
                            width: parent.width
                            text: {
                                const variant = variantEntry.modelData;
                                const target = variant.gpuPci || (variant.gpuIndex !== undefined ? `GPU ${variant.gpuIndex}` : "unassigned");
                                return variantEntry.legacy ? `${target} (legacy)` : target;
                            }
                            font.pixelSize: Theme.fontSizeSmall - 1
                            color: variantEntry.legacy ? Theme.warning : Theme.surfaceVariantText
                            elide: Text.ElideRight
                        }
                    }

                    // Segmented Button Group (Edit, Reset, Delete)
                    Row {
                        id: buttonGroupRow
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2

                        readonly property bool hasReset: resetVariantButton.visible
                        readonly property real btnGroupOuterRad: root.outerR
                        readonly property real btnGroupInnerRad: root.innerR

                        // Edit Button (First in group)
                        Rectangle {
                            id: editVariantButton
                            width: 36
                            height: 32
                            topLeftRadius: buttonGroupRow.btnGroupOuterRad
                            bottomLeftRadius: buttonGroupRow.btnGroupOuterRad
                            topRightRadius: buttonGroupRow.btnGroupInnerRad
                            bottomRightRadius: buttonGroupRow.btnGroupInnerRad

                            color: editVariantArea.containsMouse
                                ? Theme.withAlpha(Theme.primary, 0.15)
                                : Qt.rgba(Theme.secondary.r, Theme.secondary.g, Theme.secondary.b, 0.05)
                            border.width: 1
                            border.color: editVariantArea.containsMouse
                                ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.4)
                                : Qt.rgba(Theme.secondary.r, Theme.secondary.g, Theme.secondary.b, 0.15)

                            Behavior on color { ColorAnimation { duration: 150 } }
                            Behavior on border.color { ColorAnimation { duration: 150 } }

                            DankIcon {
                                anchors.centerIn: parent
                                name: "edit"
                                size: 16
                                color: editVariantArea.containsMouse ? Theme.primary : Theme.surfaceVariantText
                                Behavior on color { ColorAnimation { duration: 150 } }
                            }

                            MouseArea {
                                id: editVariantArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: variantEntry.beginEdit()
                            }
                        }

                        // Reset Button (Middle in group if visible)
                        Rectangle {
                            id: resetVariantButton
                            width: 36
                            height: 32
                            radius: buttonGroupRow.btnGroupInnerRad
                            readonly property string fallbackDefaultIcon: {
                                const mode = variantEntry.modelData.widgetDisplayMode;
                                if (mode === "vram") return "developer_board";
                                if (mode === "utilization") return "speed";
                                if (mode === "temperature") return "thermostat";
                                return "dashboard";
                            }
                            readonly property string expectedDefaultIcon: variantEntry.modelData.defaultIcon || fallbackDefaultIcon
                            visible: variantEntry.modelData.name !== variantEntry.modelData.originalName || variantEntry.modelData.icon !== expectedDefaultIcon

                            color: resetVariantArea.containsMouse
                                ? Theme.withAlpha(Theme.primary, 0.15)
                                : Qt.rgba(Theme.secondary.r, Theme.secondary.g, Theme.secondary.b, 0.05)
                            border.width: 1
                            border.color: resetVariantArea.containsMouse
                                ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.4)
                                : Qt.rgba(Theme.secondary.r, Theme.secondary.g, Theme.secondary.b, 0.15)

                            Behavior on color { ColorAnimation { duration: 150 } }
                            Behavior on border.color { ColorAnimation { duration: 150 } }

                            DankIcon {
                                anchors.centerIn: parent
                                name: "restart_alt"
                                size: 16
                                color: resetVariantArea.containsMouse ? Theme.primary : Theme.surfaceVariantText
                                Behavior on color { ColorAnimation { duration: 150 } }
                            }

                            MouseArea {
                                id: resetVariantArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    const variant = variantEntry.modelData;
                                    const originalName = variant.originalName || "AMD GPU";
                                    const defaultIcon = variant.defaultIcon || resetVariantButton.fallbackDefaultIcon;
                                    root.updateVariant(variant.id, { name: originalName, icon: defaultIcon });
                                }
                            }
                        }

                        // Delete Button (Last in group)
                        Rectangle {
                            id: deleteVariantButton
                            width: 36
                            height: 32
                            topLeftRadius: buttonGroupRow.hasReset ? buttonGroupRow.btnGroupInnerRad : buttonGroupRow.btnGroupInnerRad
                            bottomLeftRadius: buttonGroupRow.hasReset ? buttonGroupRow.btnGroupInnerRad : buttonGroupRow.btnGroupInnerRad
                            topRightRadius: buttonGroupRow.btnGroupOuterRad
                            bottomRightRadius: buttonGroupRow.btnGroupOuterRad

                            color: deleteVariantArea.containsMouse
                                ? Theme.withAlpha(Theme.error, 0.2)
                                : Qt.rgba(Theme.secondary.r, Theme.secondary.g, Theme.secondary.b, 0.05)
                            border.width: 1
                            border.color: deleteVariantArea.containsMouse
                                ? Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.5)
                                : Qt.rgba(Theme.secondary.r, Theme.secondary.g, Theme.secondary.b, 0.15)

                            Behavior on color { ColorAnimation { duration: 150 } }
                            Behavior on border.color { ColorAnimation { duration: 150 } }

                            DankIcon {
                                anchors.centerIn: parent
                                name: "delete"
                                size: 16
                                color: deleteVariantArea.containsMouse ? Theme.error : Theme.surfaceVariantText
                                Behavior on color { ColorAnimation { duration: 150 } }
                            }

                            MouseArea {
                                id: deleteVariantArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    entryDeleteAnim.restart();
                                }
                            }
                        }
                    }
                }

                Column {
                    id: editorColumn
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: Theme.spacingM
                    anchors.rightMargin: Theme.spacingM
                    visible: variantEntry.editing
                    spacing: Theme.spacingS

                    // Segmented Textbox for Widget Name
                    Rectangle {
                        id: editNameBox
                        width: parent.width
                        height: 40
                        radius: root.innerR
                        color: Theme.withAlpha(Theme.surfaceContainerHigh, 0.6)
                        border.width: editNameField.activeFocus ? 1.5 : 1
                        border.color: editNameField.activeFocus ? Theme.primary : Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.20)
                        clip: true

                        Behavior on border.color { ColorAnimation { duration: 150 } }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.spacingM
                            anchors.rightMargin: Theme.spacingM
                            spacing: Theme.spacingS

                            DankIcon {
                                name: "badge"
                                size: 18
                                color: editNameField.activeFocus ? Theme.primary : Theme.surfaceVariantText
                                Layout.alignment: Qt.AlignVCenter
                                Behavior on color { ColorAnimation { duration: 150 } }
                            }

                            TextInput {
                                id: editNameField
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                color: Theme.surfaceText
                                font.pixelSize: Theme.fontSizeSmall
                                font.weight: Font.Medium
                                maximumLength: 40
                                selectByMouse: true
                                onAccepted: variantEntry.commitEdit()

                                StyledText {
                                    anchors.fill: parent
                                    verticalAlignment: Text.AlignVCenter
                                    text: "Widget name"
                                    color: Qt.rgba(Theme.surfaceVariantText.r, Theme.surfaceVariantText.g, Theme.surfaceVariantText.b, 0.5)
                                    font.pixelSize: Theme.fontSizeSmall
                                    visible: !editNameField.text && !editNameField.activeFocus
                                }
                            }
                        }
                    }

                    Row {
                        width: parent.width
                        spacing: Theme.spacingS

                        DankIcon {
                            name: variantEntry.pendingIcon || variantEntry.pickerIcon || "dashboard"
                            size: 20
                            color: Theme.surfaceText
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        StyledText {
                            width: parent.width - 20 - Theme.spacingS
                            text: "Icon: pick from the dropdown or type a Material Symbol name."
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                            wrapMode: Text.WordWrap
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    Row {
                        width: parent.width
                        spacing: Theme.spacingS

                        // Segmented Textbox for Icon Name
                        Rectangle {
                            id: iconTextBox
                            width: Math.max(140, parent.width - iconPicker.width - Theme.spacingS)
                            height: 36
                            radius: root.innerR
                            color: Theme.withAlpha(Theme.surfaceContainerHigh, 0.6)
                            border.width: iconTextField.activeFocus ? 1.5 : 1
                            border.color: iconTextField.activeFocus ? Theme.primary : Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.20)
                            anchors.verticalCenter: parent.verticalCenter
                            clip: true

                            Behavior on border.color { ColorAnimation { duration: 150 } }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: Theme.spacingM
                                anchors.rightMargin: Theme.spacingM
                                spacing: Theme.spacingXS

                                TextInput {
                                    id: iconTextField
                                    Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignVCenter
                                    color: Theme.surfaceText
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.weight: Font.Medium
                                    maximumLength: 60
                                    selectByMouse: true
                                    onTextEdited: {
                                        variantEntry.pendingIcon = text.trim();
                                    }
                                    onAccepted: variantEntry.commitEdit()

                                    StyledText {
                                        anchors.fill: parent
                                        verticalAlignment: Text.AlignVCenter
                                        text: "e.g. dashboard"
                                        color: Qt.rgba(Theme.surfaceVariantText.r, Theme.surfaceVariantText.g, Theme.surfaceVariantText.b, 0.5)
                                        font.pixelSize: Theme.fontSizeSmall
                                        visible: !iconTextField.text && !iconTextField.activeFocus
                                    }
                                }
                            }
                        }

                        DankIconPicker {
                            id: iconPicker
                            width: 200
                            height: 36
                            currentIcon: variantEntry.pickerIcon
                            anchors.verticalCenter: parent.verticalCenter
                            onIconSelected: (iconName, iconType) => {
                                variantEntry.pickerIcon = iconName;
                                if (!iconTextField.text.trim())
                                    variantEntry.pendingIcon = iconName;
                            }
                        }
                    }

                    Row {
                        width: parent.width
                        spacing: Theme.spacingXS

                        DankIcon {
                            name: "open_in_new"
                            size: Theme.fontSizeSmall
                            color: Theme.primary
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        StyledText {
                            text: "Browse all Material Symbols"
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.primary
                            linkColor: Theme.primary

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Qt.openUrlExternally("https://fonts.google.com/icons?icon.set=Material+Symbols")
                            }
                        }
                    }

                    // Segmented Button Group (Save & Cancel)
                    Row {
                        spacing: 2

                        Rectangle {
                            id: saveBtn
                            width: 80
                            height: 34
                            topLeftRadius: root.outerR
                            bottomLeftRadius: root.outerR
                            topRightRadius: root.innerR
                            bottomRightRadius: root.innerR

                            color: saveMa.containsMouse
                                ? Theme.primary
                                : Theme.withAlpha(Theme.primary, 0.85)
                            border.width: 1
                            border.color: Theme.primary

                            Behavior on color { ColorAnimation { duration: 150 } }

                            Row {
                                anchors.centerIn: parent
                                spacing: Theme.spacingXS

                                DankIcon {
                                    name: "save"
                                    size: 16
                                    color: Theme.onPrimary || "#ffffff"
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                StyledText {
                                    text: "Save"
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.weight: Font.Bold
                                    color: Theme.onPrimary || "#ffffff"
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            MouseArea {
                                id: saveMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: variantEntry.commitEdit()
                            }
                        }

                        Rectangle {
                            id: cancelBtn
                            width: 80
                            height: 34
                            topLeftRadius: root.innerR
                            bottomLeftRadius: root.innerR
                            topRightRadius: root.outerR
                            bottomRightRadius: root.outerR

                            color: cancelMa.containsMouse
                                ? Theme.withAlpha(Theme.surfaceVariant, 0.25)
                                : Qt.rgba(Theme.secondary.r, Theme.secondary.g, Theme.secondary.b, 0.05)
                            border.width: 1
                            border.color: cancelMa.containsMouse
                                ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.4)
                                : Qt.rgba(Theme.secondary.r, Theme.secondary.g, Theme.secondary.b, 0.15)

                            Behavior on color { ColorAnimation { duration: 150 } }
                            Behavior on border.color { ColorAnimation { duration: 150 } }

                            StyledText {
                                anchors.centerIn: parent
                                text: "Cancel"
                                font.pixelSize: Theme.fontSizeSmall
                                font.weight: Font.Medium
                                color: cancelMa.containsMouse ? Theme.surfaceText : Theme.surfaceVariantText
                                Behavior on color { ColorAnimation { duration: 150 } }
                            }

                            MouseArea {
                                id: cancelMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: variantEntry.editing = false
                            }
                        }
                    }
                }
            }
        }

        StyledText {
            width: parent.width
            visible: (root.variants || []).length === 0
            text: "No widgets configured yet."
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
        }
    }
    }
}
