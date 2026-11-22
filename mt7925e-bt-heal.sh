#!/usr/bin/env bash
# mt7925e-bt-heal.sh - Script to fix MT7925e Bluetooth by reloading kernel modules.

set -e

CONFIG_FILE="/etc/mt7925e-bt-heal.conf"

# Load user configuration if present
if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
fi

# Default behavior: also reload Wi-Fi module unless overridden
: "${REMOVE_WIFI:=1}"   # if 1 (default), reload mt7925e Wi-Fi module as well; if 0, only reload btusb
: "${WAIT_SECONDS:=10}" # seconds to wait for the adapter to show up before (and after) reloading modules

if ! [[ "$WAIT_SECONDS" =~ ^[0-9]+$ ]]; then
    echo "MT7925e-BT-Heal: Invalid WAIT_SECONDS='$WAIT_SECONDS' in $CONFIG_FILE, using 10."
    WAIT_SECONDS=10
fi

usage() {
    echo "Usage: ${0##*/} [--install|--uninstall|--logs]"
    echo "  No arguments: Perform Bluetooth fix now (reload modules if needed)."
    echo "  --install   : Install and enable mt7925e-bt-heal service (runs fix at boot and after resume)."
    echo "  --uninstall : Disable service and remove installed files."
    echo "  --logs      : Show recent journal logs from mt7925e-bt-heal service."
}

bt_present() {
    [[ -n "$(ls -A /sys/class/bluetooth 2>/dev/null)" ]]
}

# The adapter can take a few seconds to appear at boot and after resume,
# so give it a chance before deciding it's missing.
wait_for_bt() {
    local i
    for ((i = 0; i < WAIT_SECONDS; i++)); do
        bt_present && return 0
        sleep 1
    done
    bt_present
}

if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    usage
    exit 0
fi

# Ensure script is run as root for any operation
if [[ $EUID -ne 0 ]]; then
    echo "Please run this script as root (using sudo) for install/uninstall or module reload."
    exit 1
fi

case "$1" in
  --install)
    echo "MT7925e-BT-Heal: Installing service and enabling automatic fix..."
    # Copy this script to /usr/bin
    install -D -m 755 "$0" "/usr/bin/mt7925e-bt-heal.sh"
    # Copy systemd service unit
    cat > /etc/systemd/system/mt7925e-bt-heal.service << 'EOF'
[Unit]
Description=MT7925e Bluetooth Heal Service
Documentation=https://github.com/moolooite/mt7925e-bt-heal
After=bluetooth.service
Wants=bluetooth.service

[Service]
Type=oneshot
ExecStart=/usr/bin/mt7925e-bt-heal.sh

[Install]
WantedBy=multi-user.target
EOF
    # Create systemd sleep hook (run after resume from suspend/hibernate)
    install -D -m 755 /dev/null "/usr/lib/systemd/system-sleep/mt7925e-bt-heal"
    cat > "/usr/lib/systemd/system-sleep/mt7925e-bt-heal" << 'EOF'
#!/bin/bash
# /usr/lib/systemd/system-sleep/mt7925e-bt-heal
# Called by systemd-sleep on suspend/resume. We only act on "post" (after resume).
# Runs the fix through the service so it shows up in the service's logs.
if [ "$1" = "post" ]; then
    systemctl start --no-block mt7925e-bt-heal.service
fi
EOF
    # Create config file, but keep an existing one so settings survive a reinstall
    if [[ -f "$CONFIG_FILE" ]]; then
        echo "MT7925e-BT-Heal: Keeping existing $CONFIG_FILE."
    else
        echo "# Configuration for MT7925e-BT-Heal" > "$CONFIG_FILE"
        echo "# Set REMOVE_WIFI=0 to avoid reloading Wi-Fi module (mt7925e) if you prefer" >> "$CONFIG_FILE"
        echo "REMOVE_WIFI=1" >> "$CONFIG_FILE"
        echo "# Seconds to wait for the Bluetooth adapter to appear before reloading modules" >> "$CONFIG_FILE"
        echo "WAIT_SECONDS=10" >> "$CONFIG_FILE"
    fi
    # Enable and start the service
    systemctl daemon-reload
    systemctl enable mt7925e-bt-heal.service
    systemctl start mt7925e-bt-heal.service
    echo "MT7925e-BT-Heal: Installation complete. Service enabled at boot and on resume."
    exit 0
    ;;
  --uninstall)
    echo "MT7925e-BT-Heal: Removing service and associated files..."
    # Stop and disable service
    systemctl stop mt7925e-bt-heal.service 2>/dev/null || true
    systemctl disable mt7925e-bt-heal.service 2>/dev/null || true
    # Remove service unit file
    rm -f /etc/systemd/system/mt7925e-bt-heal.service
    # Remove sleep hook script
    rm -f /usr/lib/systemd/system-sleep/mt7925e-bt-heal
    # Remove main script from bin
    rm -f /usr/bin/mt7925e-bt-heal.sh
    # Remove config file (optional: leave it if user modified?)
    # rm -f "$CONFIG_FILE"
    systemctl daemon-reload
    echo "MT7925e-BT-Heal: Uninstallation complete. (Note: $CONFIG_FILE not removed.)"
    exit 0
    ;;
  --logs)
    journalctl -u mt7925e-bt-heal.service -n 50 --no-pager
    exit 0
    ;;
  "")
    # No argument: perform the fix now if needed
    ;;
  *)
    echo "Unknown option: $1"
    usage
    exit 1
    ;;
esac

# Action: Check if Bluetooth controller is missing, if so, reload modules
if wait_for_bt; then
    echo "MT7925e-BT-Heal: Bluetooth adapter is present. No action needed."
    exit 0
fi

echo "MT7925e-BT-Heal: Bluetooth adapter not detected. Reloading btusb/mt7925e modules..."
# Remove modules
if [[ "$REMOVE_WIFI" -eq 1 ]]; then
    modprobe -r btusb mt7925e || echo "Warning: Failed to remove modules (btusb/mt7925e). They might not be loaded or are in use."
else
    modprobe -r btusb || echo "Warning: btusb module could not be removed (maybe not loaded?)."
fi
# Load modules back
modprobe mt7925e || echo "Warning: Failed to load mt7925e module."
modprobe btusb   || echo "Warning: Failed to load btusb module."
echo "MT7925e-BT-Heal: Module reload complete."

# Make sure the adapter actually came back
if ! wait_for_bt; then
    echo "MT7925e-BT-Heal: Bluetooth adapter still not detected after reloading modules."
    [[ "$REMOVE_WIFI" -eq 1 ]] || echo "MT7925e-BT-Heal: Try REMOVE_WIFI=1 in $CONFIG_FILE, or reboot."
    exit 1
fi
echo "MT7925e-BT-Heal: Bluetooth adapter is back."

# If bluetooth service is running, restart it to pick up the new adapter
if systemctl is-active --quiet bluetooth.service; then
    systemctl restart bluetooth.service
    echo "MT7925e-BT-Heal: Restarted bluetooth.service."
fi

exit 0
