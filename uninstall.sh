#!/usr/bin/env bash
# Remove everything install.sh put in place. Stopping the service first returns the hub
# to hardware ChatMix mode.
set -euo pipefail

SUDO=${SUDO:-sudo}

systemctl --user disable --now arctis-omni-chatmix.service 2>/dev/null || true
rm -f "$HOME/.config/systemd/user/arctis-omni-chatmix.service"
systemctl --user daemon-reload

if [ -e "$HOME/.config/pipewire/pipewire.conf.d/60-arctis-omni-chatmix.conf" ]; then
    rm -f "$HOME/.config/pipewire/pipewire.conf.d/60-arctis-omni-chatmix.conf"
    echo "Restarting PipeWire to remove the Game/Chat sinks..."
    systemctl --user restart pipewire pipewire-pulse wireplumber
fi

rm -f "$HOME/.local/bin/arctis-omni"
rm -rf "$HOME/.local/share/plasma/plasmoids/local.arctis-omni-battery"

if [ -e /etc/udev/rules.d/70-arctis-nova-pro-omni.rules ]; then
    echo "Removing udev rule (needs root)..."
    $SUDO sh -c "rm -f /etc/udev/rules.d/70-arctis-nova-pro-omni.rules && udevadm control --reload"
fi

echo "Uninstalled. Remove the widget from your panel if you added it."
