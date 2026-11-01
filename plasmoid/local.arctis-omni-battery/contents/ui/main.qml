import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.plasma5support as P5Support
import org.kde.kirigami as Kirigami

// Polls `arctis-omni status --json` and shows the headset battery in the panel.
PlasmoidItem {
    id: root

    // Absolute path filled in by install.sh; plasmashell's PATH may not include ~/.local/bin.
    readonly property string tool: "@ARCTIS_OMNI@"
    property var status: null
    property string error: ""

    readonly property bool connected: status !== null && status.connected
    // Wired models report no battery (battery is null).
    readonly property bool hasBattery: connected && status.battery !== null
    readonly property string batteryText: hasBattery ? status.battery + "%" : connected ? "Wired" : "–"

    toolTipMainText: status ? status.model : "Arctis headset"
    toolTipSubText: status && status.firmware && status.firmware.update_available ? "Firmware update available"
        : error !== "" ? error
        : hasBattery ? "Headset " + status.battery + "%"
            + (status.charger_battery !== null ? " · spare " + status.charger_battery + "%" : "")
        : connected ? "Wired headset"
        : "Headset not connected"

    P5Support.DataSource {
        id: runner
        engine: "executable"
        connectedSources: []
        onNewData: (source, data) => {
            disconnectSource(source);
            if (!source.includes("status --json")) {
                root.refresh();
                return;
            }
            if (data["exit code"] === 0) {
                try {
                    root.status = JSON.parse(data.stdout);
                    root.error = "";
                } catch (e) {
                    root.error = "Bad output from arctis-omni";
                }
            } else {
                root.status = null;
                root.error = (data.stderr || "arctis-omni failed").trim();
            }
        }
    }

    // A right-aligned row label for the popup's grid.
    component FieldLabel: PlasmaComponents.Label {
        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
        opacity: 0.8
    }

    // A battery icon, its percentage and what it powers.
    component BatteryReadout: RowLayout {
        property int percent: 0
        property bool charging: false
        property string what: ""
        spacing: Kirigami.Units.smallSpacing
        Kirigami.Icon {
            source: "battery-" + String(Math.min(100, Math.round(parent.percent / 10) * 10)).padStart(3, "0")
                + (parent.charging ? "-charging" : "")
            Layout.preferredWidth: Kirigami.Units.iconSizes.small
            Layout.preferredHeight: Kirigami.Units.iconSizes.small
        }
        PlasmaComponents.Label {
            text: parent.percent + "%"
            color: parent.percent <= 15 && !parent.charging ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
        }
        PlasmaComponents.Label {
            text: parent.what
            opacity: 0.7
        }
    }

    // Where the base station's ChatMix dial sits between Game and Chat. The dial fades one
    // side out at a time: centred is 100/100, fully towards Game is 100/0.
    component ChatMixBar: RowLayout {
        id: mix
        property int game: 100
        property int chat: 100
        readonly property real position: 0.5 + (chat - game) / 200  // 0 = Game, 1 = Chat
        spacing: Kirigami.Units.largeSpacing
        Accessible.name: "ChatMix: game " + game + "%, chat " + chat + "%"

        PlasmaComponents.Label {
            text: "Game"
            opacity: mix.position < 0.5 ? 1 : 0.7
        }
        Item {
            Layout.fillWidth: true
            implicitHeight: Kirigami.Units.gridUnit
            Rectangle {  // track
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: Math.max(2, Math.round(Kirigami.Units.smallSpacing / 2))
                radius: height / 2
                color: Kirigami.Theme.textColor
                opacity: 0.25
            }
            Rectangle {  // centre mark
                anchors.centerIn: parent
                width: 1
                height: Kirigami.Units.smallSpacing * 2
                color: Kirigami.Theme.textColor
                opacity: 0.4
            }
            Rectangle {  // the dial
                width: Kirigami.Units.smallSpacing
                height: parent.height
                radius: width / 2
                color: Kirigami.Theme.highlightColor
                x: mix.position * (parent.width - width)
                Behavior on x {
                    NumberAnimation { duration: Kirigami.Units.shortDuration; easing.type: Easing.OutCubic }
                }
            }
        }
        PlasmaComponents.Label {
            text: "Chat"
            opacity: mix.position > 0.5 ? 1 : 0.7
        }
    }

    // A stepped slider that follows the status poll and emits commit(value) when a drag
    // ends or mouse-wheel scrolling settles, so a change is one command.
    component LevelSlider: RowLayout {
        id: level
        property var status: null
        property alias from: slider.from
        property alias to: slider.to
        property var valueFrom: status => 0
        property var label: value => String(value)
        property color labelColor: Kirigami.Theme.textColor
        signal commit(int value)
        Layout.fillWidth: true

        onStatusChanged: {
            // Don't overwrite a drag, or a scroll that hasn't been sent yet.
            if (status && !slider.pressed && !settle.running)
                slider.value = valueFrom(status);
        }

        PlasmaComponents.Slider {
            id: slider
            stepSize: 1
            snapMode: PlasmaComponents.Slider.SnapAlways
            enabled: level.enabled
            Layout.fillWidth: true
            onPressedChanged: {
                if (!pressed) level.commit(value);
            }
            // The mouse wheel steps the value and emits moved() without a press.
            onMoved: {
                if (!pressed) settle.restart();
            }
            Timer {
                id: settle
                interval: 300
                onTriggered: level.commit(slider.value)
            }
        }
        PlasmaComponents.Label {
            text: level.label(slider.value)
            color: level.labelColor
            Layout.minimumWidth: Kirigami.Units.gridUnit * 2
        }
    }

    function refresh() { runner.connectSource(tool + " status --json"); }
    function run(args) { runner.connectSource(tool + " " + args); }

    // Every 10 s in the panel, every 2 s while the popup is open, so a headset that
    // connects, disconnects or changes settings shows up promptly.
    Timer {
        interval: root.expanded ? 2000 : 10000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    compactRepresentation: MouseArea {
        Layout.minimumWidth: row.implicitWidth
        Layout.preferredWidth: row.implicitWidth
        onClicked: {
            root.expanded = !root.expanded;
            if (root.expanded) root.refresh();
        }

        RowLayout {
            id: row
            anchors.fill: parent
            spacing: Kirigami.Units.smallSpacing
            Kirigami.Icon {
                source: "audio-headset"
                Layout.preferredWidth: Kirigami.Units.iconSizes.small
                Layout.preferredHeight: Kirigami.Units.iconSizes.small
            }
            PlasmaComponents.Label {
                text: root.batteryText
                color: root.hasBattery && root.status.battery <= 15 ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
            }
        }
    }

    fullRepresentation: Item {
        readonly property int margin: Kirigami.Units.largeSpacing * 2
        Layout.minimumWidth: Kirigami.Units.gridUnit * 21 + margin * 2
        Layout.preferredWidth: Layout.minimumWidth
        Layout.minimumHeight: popup.implicitHeight + margin * 2
        Layout.preferredHeight: Layout.minimumHeight
        Layout.maximumHeight: Layout.minimumHeight

        ColumnLayout {
            id: popup
            anchors.fill: parent
            anchors.margins: parent.margin
            spacing: Kirigami.Units.largeSpacing * 1.5

            readonly property var st: root.status
            readonly property string noiseMode: st && st.noise_mode ? st.noise_mode : "off"
            readonly property bool hasNoiseControl: root.connected && st.anc_writable
            // One strength slider for the active noise mode; none when it's off. The ANC level
            // only exists on models that report it (anc_level is null otherwise).
            // Hidden with the mode buttons while the headset is off.
            readonly property bool showAncLevel: noiseMode === "anc" && hasNoiseControl && st.anc_level !== null
            readonly property bool showTransparencyLevel: noiseMode === "transparency" && hasNoiseControl
            readonly property var firmware: st ? st.firmware : null

            // Model, then each battery the base station reports.
            RowLayout {
                spacing: Kirigami.Units.largeSpacing
                Kirigami.Icon {
                    source: "audio-headset"
                    Layout.preferredWidth: Kirigami.Units.iconSizes.medium
                    Layout.preferredHeight: Kirigami.Units.iconSizes.medium
                    Layout.alignment: Qt.AlignTop
                }
                ColumnLayout {
                    spacing: Kirigami.Units.largeSpacing
                    Layout.fillWidth: true
                    Kirigami.Heading {
                        level: 3
                        text: popup.st ? popup.st.model : root.error !== "" ? root.error : "No headset found"
                        wrapMode: Text.Wrap
                        Layout.fillWidth: true
                    }
                    // The spare battery charges in the base station, so it's reported
                    // whether or not the headset is on.
                    RowLayout {
                        visible: popup.st !== null && popup.st.wireless
                        spacing: Kirigami.Units.gridUnit
                        BatteryReadout {
                            visible: root.hasBattery
                            percent: root.hasBattery ? popup.st.battery : 0
                            charging: root.hasBattery && popup.st.charging
                            what: popup.st && popup.st.charging ? "headset, charging" : "headset"
                        }
                        PlasmaComponents.Label {
                            visible: !root.hasBattery
                            text: "Headset off"
                            opacity: 0.7
                        }
                        BatteryReadout {
                            visible: popup.st !== null && popup.st.charger_battery !== null
                            percent: visible ? popup.st.charger_battery : 0
                            what: "spare"
                        }
                    }
                    PlasmaComponents.Label {
                        visible: popup.st !== null && !popup.st.wireless
                        text: "Wired headset"
                        opacity: 0.7
                    }
                }
            }

            // Controls. Labels share one column so the sliders line up across groups.
            GridLayout {
                visible: popup.st !== null
                columns: 2
                // Rows within a group 12 px apart; separators add room on both sides so
                // groups read as clearly further apart than rows.
                rowSpacing: Kirigami.Units.largeSpacing * 1.5
                columnSpacing: Kirigami.Units.largeSpacing
                Layout.fillWidth: true

                Kirigami.Separator { Layout.columnSpan: 2; Layout.fillWidth: true; Layout.topMargin: Kirigami.Units.smallSpacing; Layout.bottomMargin: Kirigami.Units.smallSpacing; visible: popup.hasNoiseControl }

                RowLayout {
                    visible: popup.hasNoiseControl
                    Layout.columnSpan: 2
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing
                    Repeater {
                        model: [["off", "Off"], ["transparency", "Transparency"], ["anc", "ANC"]]
                        PlasmaComponents.Button {
                            text: modelData[1]
                            checkable: true
                            checked: popup.noiseMode === modelData[0]
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1  // equal widths
                            onClicked: root.run("anc " + modelData[0])
                        }
                    }
                }

                FieldLabel { text: "Strength"; visible: popup.showTransparencyLevel }
                LevelSlider {
                    visible: popup.showTransparencyLevel
                    status: root.status
                    enabled: root.connected
                    from: 1
                    to: 10
                    valueFrom: status => status.transparency_level
                    onCommit: value => root.run("transparency-level " + value)
                }

                FieldLabel { text: "Strength"; visible: popup.showAncLevel }
                LevelSlider {
                    visible: popup.showAncLevel
                    status: root.status
                    enabled: root.connected
                    from: 1
                    to: 3
                    valueFrom: status => status.anc_level
                    onCommit: value => root.run("anc-level " + value)
                }

                PlasmaComponents.Label {
                    visible: root.connected && popup.st.wireless && !popup.st.anc_writable
                    Layout.columnSpan: 2
                    text: "Change the noise mode on the headset"
                    opacity: 0.7
                }

                Kirigami.Separator { Layout.columnSpan: 2; Layout.fillWidth: true; Layout.topMargin: Kirigami.Units.smallSpacing; Layout.bottomMargin: Kirigami.Units.smallSpacing }

                FieldLabel { text: "Mic level" }
                LevelSlider {
                    status: root.status
                    enabled: root.connected
                    from: 1
                    to: 10
                    valueFrom: status => status.mic_volume
                    // mic_muted is null on wired models, which don't report it.
                    readonly property bool muted: popup.st !== null && popup.st.mic_muted === true
                    label: value => muted ? "Muted" : String(value)
                    labelColor: muted ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
                    onCommit: value => root.run("mic-volume " + value)
                }

                FieldLabel { text: "Sidetone" }
                LevelSlider {
                    status: root.status
                    enabled: root.connected
                    // 0 = off, 1-max = on at that level (max is per model).
                    from: 0
                    to: popup.st ? popup.st.sidetone_max : 10
                    valueFrom: status => status.sidetone_on ? status.sidetone_level : 0
                    label: value => value === 0 ? "Off" : String(value)
                    onCommit: value => root.run("sidetone " + (value === 0 ? "off" : value))
                }

                Kirigami.Separator { Layout.columnSpan: 2; Layout.fillWidth: true; Layout.topMargin: Kirigami.Units.smallSpacing; Layout.bottomMargin: Kirigami.Units.smallSpacing }

                ChatMixBar {
                    Layout.columnSpan: 2
                    Layout.fillWidth: true
                    game: popup.st ? popup.st.chatmix_game : 100
                    chat: popup.st ? popup.st.chatmix_chat : 100
                }

                // From the daily firmware check (null until it has run with this headset connected).
                Kirigami.Separator { Layout.columnSpan: 2; Layout.fillWidth: true; Layout.topMargin: Kirigami.Units.smallSpacing; Layout.bottomMargin: Kirigami.Units.smallSpacing; visible: popup.firmware !== null }
                RowLayout {
                    visible: popup.firmware !== null
                    Layout.columnSpan: 2
                    Layout.fillWidth: true
                    readonly property bool update: popup.firmware !== null && popup.firmware.update_available
                    PlasmaComponents.Label {
                        text: parent.update ? "Firmware update available" : "Firmware up to date"
                        color: parent.update ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.textColor
                        opacity: parent.update ? 1 : 0.7
                        Layout.fillWidth: true
                    }
                    PlasmaComponents.Button {
                        visible: parent.update
                        text: "Update…"
                        icon.name: "system-software-update"
                        onClicked: {
                            root.run("firmware open");
                            root.expanded = false;
                        }
                    }
                }
            }
        }
    }
}
