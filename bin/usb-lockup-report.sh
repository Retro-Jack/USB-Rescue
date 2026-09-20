#!/usr/bin/env bash
#
# usb-lockup-report.sh — take a snapshot while the keyboard and mouse are dead.
#
# Run this over SSH from a phone or another machine the moment a lockup
# happens, BEFORE shutting down: the evidence dies with the reboot.
#
#     ssh you@your-machine 'bin/usb-lockup-report.sh'
#
# It writes /mnt/misc/lockup-reports/<timestamp>.txt (or ~/lockup-reports if
# /mnt/misc is not mounted) and prints a short verdict. Reads only — it changes
# nothing. Use usb-recover.sh afterwards to try to get input back.
#
set -u

OUT_DIR=/mnt/misc/lockup-reports
[[ -d /mnt/misc ]] || OUT_DIR="${HOME}/lockup-reports"
mkdir -p "${OUT_DIR}"
OUT="${OUT_DIR}/$(date +%Y-%m-%d_%H-%M-%S).txt"

# The kernel log needs root here (kernel.dmesg_restrict=1); journalctl -k does
# not, so use that and fall back to dmesg if it is ever readable.
say() { printf '%s\n' "$*" | tee -a "${OUT}"; }
section() { printf '\n===== %s\n' "$*" >> "${OUT}"; }

say "USB lockup report — $(date '+%d/%m/%Y %H:%M:%S')"
say "uptime:$(uptime -p | sed 's/^up//')"

section "kernel log, last 15 minutes"
journalctl -k --since "-15min" --no-pager >> "${OUT}" 2>&1

section "USB and input messages, last 30 minutes"
journalctl --since "-30min" --no-pager 2>&1 |
    grep -i -E "usb|xhci|hid|input|libinput|kwin|plasmashell" >> "${OUT}"

section "USB tree"
lsusb -t >> "${OUT}" 2>&1
lsusb >> "${OUT}" 2>&1

section "devices still enumerated"
for d in /sys/bus/usb/devices/[0-9]*-[0-9]*; do
    [[ -f "${d}/product" ]] || continue
    printf '%-12s %-34s %s\n' "$(basename "${d}")" \
        "$(cat "${d}/product" 2>/dev/null)" \
        "$(cat "${d}/power/runtime_status" 2>/dev/null)" >> "${OUT}"
done

section "input devices the kernel knows about"
cat /proc/bus/input/devices >> "${OUT}" 2>&1

section "are keypresses still arriving? (5 second sample per device)"
# Reading an event device shows whether HID traffic reaches the kernel at all.
# Ask the person at the machine to mash a key while this runs.
for ev in /dev/input/by-id/*-event-kbd /dev/input/by-id/*-event-mouse; do
    [[ -e "${ev}" ]] || continue
    count=$(timeout 5 cat "${ev}" 2>/dev/null | wc -c)
    printf '%-60s %s bytes in 5s\n' "$(basename "${ev}")" "${count}" >> "${OUT}"
done

section "compositor and input stack processes"
ps -o pid,stat,etime,pcpu,comm -C kwin_wayland,plasmashell,Xwayland 2>/dev/null >> "${OUT}"

section "load, memory, freezes"
uptime >> "${OUT}"; free -h >> "${OUT}"
ps -eo stat,pid,comm | awk '$1 ~ /D/ {print}' >> "${OUT}"   # uninterruptible sleep

# ---- verdict -------------------------------------------------------------
kb=$(grep -c "USB Keyboard" "${OUT}")
errs=$(journalctl -k --since "-15min" --no-pager 2>/dev/null |
       grep -c -i -E "xhci|not responding|disconnect|reset")
say ""
say "Written to: ${OUT}"
say "Keyboard still enumerated: $([[ ${kb} -gt 0 ]] && echo yes || echo NO)"
say "USB-ish kernel messages in the last 15 min: ${errs}"
say ""
say "The keypress sample in the report only means something if someone was"
say "pressing keys while it ran — 0 bytes with nobody typing proves nothing."
say ""
say "Next: bin/usb-recover.sh   (tries to bring input back without a reboot)"
