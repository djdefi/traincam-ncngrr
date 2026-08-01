#!/usr/bin/env bash
# Trim boot-time services the Pi 5 kiosk appliance does not need, so the
# lightdm autologin session - and therefore the picture - comes up sooner.
# Run ON the Pi 5.
#
# WHY: on the kiosk, systemd *started* NetworkManager at 22.9s but the process
# did not actually fork until 57.8s; lightdm the same (58s -> 92s); autologin
# only opened the session at 132.8s, and the browser's first GET landed at
# ~303s. Nothing was "slow" in isolation - the SD card was IO-starved by
# several multi-user services running concurrently at boot (e2scrub_reap alone
# took 69s; `lightdm: Error updating user ... Timeout was reached` is the
# starved accounts-daemon). Removing units this appliance has no use for frees
# the card so the session logs in far earlier.
#
# Every unit here is justified below and is trivially reversible:
#   scripts/optimize-boot.sh --uninstall   # unmask / re-enable everything
#
# Deliberately NOT touched: wayvnc (remote support for the show),
# xdg-desktop-portal ordering, and the traincam kiosk units.
#
# Idempotent. Needs root (uses sudo -n, like setup-kiosk.sh's blanking step).
set -euo pipefail

# unit : one-line reason the kiosk does not need it at boot
MASK=(
  e2scrub_reap.service       # reaps ext4-online-scrub LVM snapshots; this box has no LVM (single ext4 mmcblk0p2)
  ModemManager.service       # probes serial ports for cellular modems; there is no modem
  rpi-eeprom-update.service  # checks/stages Pi bootloader firmware updates; offline appliance, reversible
  cups.service               # CUPS print server; the kiosk never prints
  cups-browsed.service       # CUPS network-printer discovery; ditto
  packagekit.service         # background software-update daemon; the appliance does not self-update
)
# Blocks network-online.target until the network is up. Only cups-browsed,
# packagekit and rpc-statd-notify want that target and none are needed here;
# the WHEP viewer reconnects on its own once wifi associates, so nothing has to
# block boot on the network. Disabled rather than masked (the unit stays
# available for manual `systemctl start` if ever wanted).
WAIT_ONLINE=NetworkManager-wait-online.service

if [[ "${1:-}" == "--uninstall" ]]; then
  for u in "${MASK[@]}"; do sudo -n systemctl unmask "$u" 2>/dev/null || true; done
  sudo -n systemctl enable "$WAIT_ONLINE" 2>/dev/null || true
  sudo -n systemctl daemon-reload 2>/dev/null || true
  echo "reverted: units unmasked, $WAIT_ONLINE re-enabled. Reboot to restore original boot."
  exit 0
fi

if ! sudo -n true 2>/dev/null; then
  echo "ERROR: need passwordless sudo to mask system units. Run on the kiosk as the train user." >&2
  exit 1
fi

for u in "${MASK[@]}"; do
  if sudo -n systemctl mask --now "$u" 2>/dev/null; then
    echo "masked  $u"
  else
    echo "WARNING: could not mask $u (already masked or absent)" >&2
  fi
done

if sudo -n systemctl disable --now "$WAIT_ONLINE" 2>/dev/null; then
  echo "disabled $WAIT_ONLINE"
else
  echo "WARNING: could not disable $WAIT_ONLINE" >&2
fi

sudo -n systemctl daemon-reload 2>/dev/null || true
echo
echo "done. Reboot to measure. Reverse with: $0 --uninstall"
