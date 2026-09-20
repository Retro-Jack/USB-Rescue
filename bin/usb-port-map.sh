#!/usr/bin/env bash
#
# usb-port-map.sh — work out which physical socket is which USB port.
#
# The rear panel is a row of identical sockets and the kernel names them by
# number, so this pairs the two up: plug one device into each socket in turn
# and it prints what appeared where.
#
#     ~/bin/usb-port-map.sh
#
# Use any USB device — a stick, the keyboard, anything. Work along the panel
# in a fixed order (say top to bottom, left to right as you face the back of
# the case) and keep to that order; the numbering it prints is the order you
# plugged them in, so the list can be read straight onto a photo afterwards.
#
# You cannot see the screen from behind the case, so it SPEAKS each socket as
# you plug it in — "one, bus three port six" — through the speakers. Wait for
# it to speak before moving to the next socket. If a socket stays silent,
# nothing enumerated there: a dead socket, worth knowing in itself.
#
# Ctrl-C to finish. Everything is saved to ~/usb-port-map.txt, and the rescue
# page on your phone shows the same list.
#
# Silence it with:      SPEAK=0 ~/bin/usb-port-map.sh
# Change the pace with:  SPEECH_RATE=-50 ~/bin/usb-port-map.sh   (-100 slowest)
#
set -u

LOG="${HOME}/usb-port-map.txt"
SPEAK="${SPEAK:-1}"
SPEECH_RATE="${SPEECH_RATE:--40}"     # spd-say scale: -100 slowest, 100 fastest
: > "${LOG}"

# Speak, if we can, without holding up the next insertion.
say() {
    [[ "${SPEAK}" == "1" ]] || return 0
    command -v spd-say >/dev/null || return 0
    spd-say -w -r "${SPEECH_RATE}" "$1" >/dev/null 2>&1 &
}

echo "Plug a device into each rear socket in turn, in a fixed order."
echo "Each one is spoken aloud, so you do not need to see this screen."
echo "Waiting... (Ctrl-C when done; saved to ${LOG})"
echo
say "ready"

n=0
# Kernel lines look like:  usb 3-6.5.4: new full-speed USB device number 24 ...
journalctl -k -f -o cat --since now 2>/dev/null |
while IFS= read -r line; do
    case "${line}" in
        *"new "*"USB device number"*)
            port=$(printf '%s' "${line}" | sed -E 's/^usb ([0-9]+-[0-9.]+):.*/\1/')
            speed=$(printf '%s' "${line}" | sed -E 's/.*new ([a-zA-Z-]+) USB device.*/\1/')
            bus=${port%%-*}
            # Which controller this bus belongs to, read from sysfs rather
            # than from a list that would only suit one machine.
            ctrl=$(readlink -f "/sys/bus/usb/devices/usb${bus}" 2>/dev/null)
            ctrl=$(printf '%s' "${ctrl}" | grep -oE '[0-9a-f]{4}:[0-9a-f]{2}:[0-9a-f]{2}\.[0-9]' | tail -1)
            ctrl="${ctrl:-unknown}"
            n=$((n + 1))
            printf '%2d. socket → port %-10s %-12s controller %s\n' \
                "${n}" "${port}" "${speed}" "${ctrl}" | tee -a "${LOG}"
            # "3, bus 3 port 6" — the count first, so a missed socket is obvious.
            # Spaced out and spelled digit by digit: clearer from behind a case.
            say "number ${n}, bus ${bus}, port $(printf '%s' "${port#*-}" | sed 's/[.-]/ point /g')"
            ;;
        *"USB disconnect"*)
            port=$(printf '%s' "${line}" | sed -E 's/^usb ([0-9]+-[0-9.]+):.*/\1/')
            printf '    (unplugged %s)\n' "${port}"
            ;;
    esac
done
