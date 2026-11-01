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
    readonly property string batteryIcon: {
        if (!hasBattery) return "audio-headset";
        const level = Math.min(100, Math.round(status.battery / 10) * 10);
        return "battery-" + String(level).padStart(3, "0") + (status.charging ? "-charging" : "");
    }

    toolTipMainText: status ? status.model : "Arctis headset"
    toolTipSubText: error !== "" ? error
        : hasBattery ? "Headset " + status.battery + "% · spare " + status.charger_battery + "%"
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

    function refresh() { runner.connectSource(tool + " status --json"); }
    function run(args) { runner.connectSource(tool + " " + args); }

    Timer {
        interval: 60000
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

    fullRepresentation: ColumnLayout {
        Layout.minimumWidth: Kirigami.Units.gridUnit * 20
        Layout.preferredWidth: Kirigami.Units.gridUnit * 20
        Layout.minimumHeight: implicitHeight
        Layout.preferredHeight: implicitHeight
        Layout.maximumHeight: implicitHeight
        spacing: Kirigami.Units.smallSpacing

        RowLayout {
            Kirigami.Icon {
                source: root.batteryIcon
                Layout.preferredWidth: Kirigami.Units.iconSizes.medium
                Layout.preferredHeight: Kirigami.Units.iconSizes.medium
            }
            ColumnLayout {
                spacing: 0
                Layout.fillWidth: true
                Kirigami.Heading {
                    level: 3
                    text: root.status ? root.status.model : root.error !== "" ? root.error : "No headset found"
                    wrapMode: Text.Wrap
                    Layout.fillWidth: true
                }
                PlasmaComponents.Label {
                    visible: root.status !== null
                    text: root.hasBattery ? "Headset " + root.status.battery + "%" + (root.status.charging ? " (charging)" : "")
                        : root.connected ? "Wired headset" : "Headset not connected"
                    Layout.fillWidth: true
                }
            }
        }

        Kirigami.FormLayout {
            wideMode: true
            visible: root.status !== null
            Layout.fillWidth: true
            PlasmaComponents.Label {
                visible: root.status !== null && root.status.wireless
                Kirigami.FormData.label: "Spare battery:"
                text: root.status ? root.status.charger_battery + "%" : ""
            }
            PlasmaComponents.Label {
                visible: root.status !== null && root.status.wireless
                Kirigami.FormData.label: "Noise mode:"
                // anc_level is null on models that only report the noise mode.
                text: !root.status ? "" : root.status.noise_mode === "anc"
                    ? "ANC" + (root.status.anc_level !== null ? " (level " + root.status.anc_level + "/3)" : "")
                    : root.status.noise_mode === "transparency" ? "Transparency (level " + root.status.transparency_level + "/10)"
                    : "Off"
            }
            RowLayout {
                Kirigami.FormData.label: "Sidetone:"
                Layout.fillWidth: true
                // 0 = off, 1-max = on at that level (max is per model); sent on release so a
                // drag is one command.
                PlasmaComponents.Slider {
                    id: sidetoneSlider
                    from: 0
                    to: root.status ? root.status.sidetone_max : 10
                    stepSize: 1
                    snapMode: PlasmaComponents.Slider.SnapAlways
                    enabled: root.connected
                    Layout.fillWidth: true
                    function apply() { root.run("sidetone " + (value === 0 ? "off" : value)); }
                    onPressedChanged: {
                        if (!pressed) apply();
                    }
                    // The mouse wheel steps the value and emits moved() without a press, so
                    // wait for the scrolling to settle and send once.
                    onMoved: {
                        if (!pressed) wheelSettle.restart();
                    }
                    Timer {
                        id: wheelSettle
                        interval: 300
                        onTriggered: sidetoneSlider.apply()
                    }
                    Connections {
                        target: root
                        function onStatusChanged() {
                            if (!sidetoneSlider.pressed && root.status)
                                sidetoneSlider.value = root.status.sidetone_on ? root.status.sidetone_level : 0;
                        }
                    }
                }
                PlasmaComponents.Label {
                    text: sidetoneSlider.value === 0 ? "Off" : sidetoneSlider.value
                    Layout.minimumWidth: Kirigami.Units.gridUnit * 1.5
                }
            }
            PlasmaComponents.Label {
                Kirigami.FormData.label: "Mic:"
                text: !root.status ? "" : "Volume " + root.status.mic_volume + "/10" + (root.status.mic_muted === true ? ", muted" : "")
            }
            PlasmaComponents.Label {
                Kirigami.FormData.label: "ChatMix:"
                text: root.status ? "Game " + root.status.chatmix_game + "% · Chat " + root.status.chatmix_chat + "%" : ""
            }
        }

        RowLayout {
            visible: root.connected && root.status.anc_writable
            Layout.alignment: Qt.AlignHCenter
            Repeater {
                model: [["off", "Off"], ["transparency", "Transparency"], ["anc", "ANC"]]
                PlasmaComponents.Button {
                    text: modelData[1]
                    checkable: true
                    checked: root.status !== null && root.status.noise_mode === modelData[0]
                    onClicked: root.run("anc " + modelData[0])
                }
            }
        }

        PlasmaComponents.Label {
            visible: root.connected && root.status.wireless && !root.status.anc_writable
            text: "Change the noise mode on the headset"
            opacity: 0.7
            Layout.alignment: Qt.AlignHCenter
        }
    }
}
