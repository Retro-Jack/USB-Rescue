#!/usr/bin/env bash
#
# usb-hc-watchdog.sh — rebind the USB controller when the kernel declares it dead.
#
# On 20/09/2026 the controller at 0000:07:00.3 stopped answering:
#
#     xhci_hcd 0000:07:00.3: xHCI host not responding to stop endpoint command
#     xhci_hcd 0000:07:00.3: xHCI host controller not responding, assume dead
#     xhci_hcd 0000:07:00.3: HC died; cleaning up
#
# Every device on it — keyboard, mouse, headset, card reader — disconnected at
# once, and the machine sat unusable for nearly two hours until the controller
# was rebound by hand. The kernel announces the failure the moment it happens,
# so this watches for that and does the rebind itself, in about ten seconds.
#
# Run by usb-hc-watchdog.service. Recovery goes through
# /usr/local/sbin/usb-reset-chain.sh, the same script the rescue page uses.
#
#   --test   read the log from standard input instead of the journal, so the
#            matching can be checked without breaking anything:
#              printf 'xhci_hcd 0000:07:00.3: HC died; cleaning up\n' | \
#                  usb-hc-watchdog.sh --test
#
set -u

# Settings live in /etc/usb-rescue.conf; the defaults below are only a fallback.
# shellcheck source=/dev/null
[[ -r /etc/usb-rescue.conf ]] && . /etc/usb-rescue.conf

CONTROLLER="${CONTROLLER:-0000:07:00.3}"
HELPER="/usr/local/sbin/usb-reset-chain.sh"
COOLDOWN=120          # seconds to ignore further deaths after acting
MAX_PER_HOUR=5        # beyond this, stop acting and leave it for a human

# Lines that mean the controller has stopped answering. "HC died" is the
# decisive one; the other two precede it and are matched so a partial failure
# is caught too.
PATTERN="xhci_hcd ${CONTROLLER}.*(HC died|host controller not responding|not responding to stop endpoint)"

TEST=0
[[ "${1:-}" == "--test" ]] && TEST=1

last=0
declare -a recent=()

note() { printf '%s\n' "$*"; }   # systemd captures stdout into the journal

recover() {
    local now=$1
    if [[ -x "${HELPER}" ]]; then
        note "controller ${CONTROLLER} declared dead — rebinding"
        "${HELPER}" controller 2>&1 | sed 's/^/  /'
        note "rebind finished"
    else
        note "controller ${CONTROLLER} declared dead, but ${HELPER} is missing"
    fi
}

handle() {
    local now
    now=$(date +%s)

    # One failure produces three lines; act once.
    if (( now - last < COOLDOWN )); then
        return
    fi

    # Keep only the last hour's actions, and stop if they are piling up:
    # a controller that dies repeatedly is a hardware problem, not something
    # to paper over every two minutes.
    local kept=() t
    for t in "${recent[@]:-}"; do
        [[ -n "${t}" ]] && (( now - t < 3600 )) && kept+=("${t}")
    done
    recent=("${kept[@]:-}")
    if (( ${#recent[@]} >= MAX_PER_HOUR )); then
        note "controller died ${#recent[@]} times in the last hour — not rebinding again; this needs looking at"
        last=${now}
        return
    fi

    last=${now}
    recent+=("${now}")
    recover "${now}"
}

if (( TEST )); then
    note "test mode: reading standard input"
    while IFS= read -r line; do
        [[ "${line}" =~ $PATTERN ]] && { note "matched: ${line}"; note "(test mode — not rebinding)"; }
    done
    exit 0
fi

note "watching for ${CONTROLLER} failures"
# --since now so a death from a previous boot cannot trigger a rebind at start-up.
journalctl -k -f -o cat --since now 2>/dev/null |
while IFS= read -r line; do
    [[ "${line}" =~ $PATTERN ]] && handle
done
