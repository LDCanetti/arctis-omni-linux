#!/usr/bin/env bash
# Install arctis-omni for the current user. The udev rule needs root and is installed
# with $SUDO (default: sudo; e.g. SUDO=pkexec ./install.sh for a graphical prompt).
# Re-running only restarts what actually changed.
set -euo pipefail
cd "$(dirname "$0")"

SUDO=${SUDO:-sudo}

# The pacman package installs the same pieces system-wide; both together would load the
# Game/Chat outputs twice.
if [ -e /usr/bin/arctis-omni ]; then
    echo "arctis-omni is already installed system-wide (pacman package); not installing per user." >&2
    exit 1
fi
BIN_DIR="$HOME/.local/bin"
SYSTEMD_DIR="$HOME/.config/systemd/user"
PIPEWIRE_DIR="$HOME/.config/pipewire/pipewire.conf.d"
PLASMOID_DIR="$HOME/.local/share/plasma/plasmoids/local.arctis-omni-battery"
UDEV_RULE=/etc/udev/rules.d/70-arctis-nova-pro-omni.rules

# install_if_changed SRC DEST MODE: copies only when content differs; returns 0 if it copied,
# 1 if unchanged. A failed copy exits here, since callers' `&&` chains suspend set -e.
install_if_changed() {
    if cmp -s "$1" "$2"; then
        return 1
    fi
    install -Dm"$3" "$1" "$2" || { echo "error: could not install $2" >&2; exit 1; }
}

if ! cmp -s udev/70-arctis-nova-pro-omni.rules "$UDEV_RULE"; then
    echo "Installing udev rule (needs root)..."
    $SUDO sh -c "install -Dm644 '$PWD/udev/70-arctis-nova-pro-omni.rules' '$UDEV_RULE' \
        && udevadm control --reload && udevadm trigger --action=change --subsystem-match=hidraw"
fi

bin_changed=0
install_if_changed bin/arctis-omni "$BIN_DIR/arctis-omni" 755 && bin_changed=1

pipewire_changed=0
install_if_changed pipewire/60-arctis-omni-chatmix.conf "$PIPEWIRE_DIR/60-arctis-omni-chatmix.conf" 644 && pipewire_changed=1

service_changed=0
install_if_changed systemd/arctis-omni-chatmix.service "$SYSTEMD_DIR/arctis-omni-chatmix.service" 644 && service_changed=1

# The widget needs the tool's absolute path: plasmashell's PATH may not include ~/.local/bin.
staged=$(mktemp -d)
trap 'rm -rf "$staged"' EXIT
cp -r plasmoid/local.arctis-omni-battery/. "$staged"
sed -i "s|@ARCTIS_OMNI@|$BIN_DIR/arctis-omni|" "$staged/contents/ui/main.qml"
plasmoid_changed=0
if ! diff -rq "$staged" "$PLASMOID_DIR" >/dev/null 2>&1; then
    mkdir -p "$PLASMOID_DIR"
    cp -r "$staged/." "$PLASMOID_DIR"
    plasmoid_changed=1
fi

if [ "$pipewire_changed" = 1 ]; then
    echo "Restarting PipeWire to load the Game/Chat sinks (audio drops for a moment)..."
    systemctl --user restart pipewire pipewire-pulse wireplumber
    sleep 2
fi

systemctl --user daemon-reload
if systemctl --user is-active --quiet arctis-omni-chatmix.service; then
    if [ $((bin_changed + service_changed + pipewire_changed)) -gt 0 ]; then
        systemctl --user restart arctis-omni-chatmix.service
    fi
else
    systemctl --user enable --now arctis-omni-chatmix.service
fi

echo "Installed."
# The service and widget use absolute paths; only interactive use of the CLI needs PATH.
case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *)
        echo "  - $BIN_DIR is not on your PATH, so 'arctis-omni' won't be found in a shell."
        echo "    For bash/zsh, add this to ~/.bashrc or ~/.zshrc:  export PATH=\"\$HOME/.local/bin:\$PATH\""
        echo "    (or run it as $BIN_DIR/arctis-omni)"
        ;;
esac
echo "  - Set your default output to \"Arctis Game\" and your voice app's output to \"Arctis Chat\"."
if [ "$plasmoid_changed" = 1 ]; then
    echo "  - Widget updated: add \"Arctis Headset Battery\" to a panel, or run"
    echo "    'systemctl --user restart plasma-plasmashell' to reload an existing one."
fi
