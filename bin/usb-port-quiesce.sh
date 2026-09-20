#!/usr/bin/env bash
#
# usb-port-quiesce.sh — switch off the dead socket on the desk hub.
#
# Port 2 of the inner desk hub (3-6.5) has something on it the kernel cannot
# bring up. At every boot, and after every hub reset, it tries four times,
# power-cycles the port and gives up — about three seconds of retries:
#
#     usb 3-6.5-port2: Cannot enable. Maybe the USB cable is bad?
#     usb 3-6.5-port2: attempt power cycle
#     usb 3-6.5-port2: unable to enumerate USB device
#
# That is the only hardware fault in this machine's logs, and it sits on the
# same hub as the mouse and headset — both of which die in the lockups we are
# chasing. Disabling the port stops the retries.
#
# Reversible, and it affects nothing else:
#     echo 0 | sudo tee /sys/bus/usb/devices/3-6.5:1.0/3-6.5-port2/disable
# To find it again, or after the hardware moves:
#     for p in /sys/bus/usb/devices/*:1.0/*-port*; do \
#         echo "$p $(cat $p/state)"; done
#
# Run at boot by usb-port-quiesce.service, and again by usb-reset-chain.sh
# after a hub reset, since a reset clears it.
#
set -u

# Settings live in /etc/usb-rescue.conf; the defaults below are only a fallback.
# shellcheck source=/dev/null
[[ -r /etc/usb-rescue.conf ]] && . /etc/usb-rescue.conf

PORT="${QUIESCE_PORT:-}"
[[ -n "${PORT}" ]] || exit 0      # nothing configured: nothing to do

# The hub may not have enumerated yet at boot; wait a little for it.
for _ in $(seq 20); do
    [[ -w "${PORT}/disable" ]] && break
    sleep 1
done

if [[ ! -w "${PORT}/disable" ]]; then
    echo "usb-port-quiesce: ${PORT} not present — hub moved or unplugged?" >&2
    exit 0          # not an error: the hub simply is not there
fi

state=$(cat "${PORT}/state" 2>/dev/null)
if [[ "${state}" == "configured" ]]; then
    echo "usb-port-quiesce: port is in use (state=${state}) — leaving it alone" >&2
    exit 0          # something works there now; do not cut it off
fi

echo 1 > "${PORT}/disable"
echo "usb-port-quiesce: disabled ${PORT##*/} (was state=${state})"
