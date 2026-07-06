#!/bin/bash

#############################################################################
# Runtime Diagnostic Script - AIC8800D80 Driver
#
# The install completed but the Wi-Fi device does not work. This script
# walks the whole chain from "is the module built" to "is there a wlan
# interface" and prints exactly where it breaks.
#
# Usage:
#   chmod +x runtime_diagnostic.sh
#   sudo ./runtime_diagnostic.sh
#
# Then copy ALL of the output and share it.
#############################################################################

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

section() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

if [ "$EUID" -ne 0 ]; then
    echo -e "${YELLOW}Please run with sudo so dmesg and rfkill are readable:${NC}"
    echo "  sudo ./runtime_diagnostic.sh"
    exit 1
fi

section "0. System / kernel"
echo "Distro:  $( (. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME") || echo unknown)"
echo "Kernel:  $(uname -r)"
echo "Arch:    $(uname -m)"
echo -n "Secure Boot: "
if command -v mokutil >/dev/null 2>&1; then
    mokutil --sb-state 2>/dev/null || echo "unknown"
else
    echo "mokutil not installed (unknown)"
fi

section "1. USB device — is the adapter seen, and in which mode?"
echo "Full lsusb:"
lsusb
echo ""
echo -e "${YELLOW}Looking for AIC / known dongle IDs...${NC}"
# a69c = AIC v1, 368b = AIC v2, 1111:1111 = Pandora clone in storage mode,
# storage/CD-ROM IDs a69c:57xx come from a device that has NOT mode-switched.
lsusb | grep -iE "a69c|368b|1111:1111|Tenda|AICSemi|AIC " || echo -e "${RED}No AIC-family device found in lsusb.${NC}"
echo ""
echo "Storage/CD-ROM mode IDs (means it did NOT switch to Wi-Fi mode):"
lsusb | grep -iE "a69c:57|1111:1111" && echo -e "${RED}--> Device is still in mass-storage/CD-ROM mode.${NC}" || echo "  (none — good, it is not stuck in storage mode)"

section "2. Kernel modules — are the driver modules loaded?"
echo "lsmod | grep aic:"
lsmod | grep -i aic || echo -e "${RED}No aic modules currently loaded.${NC}"
echo ""
echo "Are the modules built and installed for this kernel?"
for m in aic8800_fdrv aic_load_fw; do
    path=$(modinfo -n "$m" 2>/dev/null)
    if [ -n "$path" ]; then
        echo -e "  ${GREEN}✓${NC} $m -> $path"
    else
        echo -e "  ${RED}✗${NC} $m not found by modinfo (not built/installed for $(uname -r))"
    fi
done
echo ""
echo "DKMS status:"
command -v dkms >/dev/null 2>&1 && dkms status || echo "  dkms not installed"

section "3. Try loading the module now"
echo "modprobe aic_load_fw ; modprobe aic8800_fdrv"
modprobe aic_load_fw 2>&1
modprobe aic8800_fdrv 2>&1 && echo -e "${GREEN}modprobe returned success${NC}" || echo -e "${RED}modprobe failed (see message above)${NC}"
echo ""
echo "lsmod | grep aic (after modprobe):"
lsmod | grep -i aic || echo -e "${RED}Still no aic modules loaded.${NC}"

section "4. Firmware present?"
if [ -d /lib/firmware ]; then
    echo "aic8800* firmware directories under /lib/firmware:"
    find /lib/firmware -maxdepth 1 -iname 'aic8800*' -type d 2>/dev/null || true
    echo ""
    echo "Contents of aic8800D80 (the D80 variant):"
    ls -la /lib/firmware/aic8800D80 2>/dev/null || echo -e "${RED}  /lib/firmware/aic8800D80 missing${NC}"
else
    echo -e "${RED}/lib/firmware does not exist?!${NC}"
fi

section "5. udev rules + usb_modeswitch installed?"
ls -la /usr/lib/udev/rules.d/aic.rules /lib/udev/rules.d/aic.rules 2>/dev/null || echo -e "${YELLOW}aic.rules not found in udev rules.d${NC}"
echo ""
echo -n "usb_modeswitch binary: "
command -v usb_modeswitch || echo -e "${RED}NOT INSTALLED (apt install usb-modeswitch)${NC}"
echo "usb_modeswitch.d config:"
ls -la /etc/usb_modeswitch.d/ 2>/dev/null || echo "  /etc/usb_modeswitch.d missing"

section "6. Network interfaces — did a wlan interface appear?"
echo "ip link (wlan* / wlp*):"
ip -br link show 2>/dev/null | grep -iE "wl|wlan" || echo -e "${RED}No wireless interface present.${NC}"
echo ""
echo "iw dev:"
command -v iw >/dev/null 2>&1 && iw dev || echo "  iw not installed (apt install iw)"

section "7. rfkill — is Wi-Fi soft/hard blocked?"
command -v rfkill >/dev/null 2>&1 && rfkill list || echo "  rfkill not installed"

section "8. Kernel log (dmesg) — driver + firmware messages"
echo "Last aic / firmware / usb related lines:"
dmesg | grep -iE "aic|8800|firmware|usb-storage|usb_modeswitch" | tail -60 || echo "  (nothing matched)"

section "9. NetworkManager"
if command -v nmcli >/dev/null 2>&1; then
    nmcli -t radio 2>/dev/null || nmcli radio 2>/dev/null
    echo ""
    nmcli device status 2>/dev/null | head -20
else
    echo "  nmcli not present"
fi

echo ""
echo -e "${GREEN}Done. Copy ALL output above (from section 0) and share it.${NC}"
