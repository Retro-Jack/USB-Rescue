#!/usr/bin/env bash
#
# usb-reset-chain.sh — the root half of the USB rescue page.
#
#     usb-reset-chain.sh hubs         reset the two hubs the keyboard sits behind
#     usb-reset-chain.sh controller   unbind/rebind the whole USB controller
#     usb-reset-chain.sh state        print what is on that bus (no changes)
#
# Installed at /usr/local/sbin/ and allowed for user jack, without a password,
# by /etc/sudoers.d/usb-rescue — those two exact command lines and nothing
# else, so the web page can call it while the keyboard is dead.
#
# "controller" drops every device on PCI 0000:07:00.3 for a few seconds: the
# keyboard, mouse, USB sound card and card reader. The external drives are on
# a different controller and are not touched. Neither action writes to a disk.
#
set -u

# Settings live in /etc/usb-rescue.conf; the defaults below are only a fallback.
# shellcheck source=/dev/null
[[ -r /etc/usb-rescue.conf ]] && . /etc/usb-rescue.conf

CONTROLLER="${CONTROLLER:-0000:07:00.3}"
read -r -a HUBS <<< "${HUBS:-3-6 3-6.5}"

state() {
    echo "USB bus 3 (the keyboard's bus):"
    lsusb -t 2>/dev/null | sed -n '/Bus 003/,/^\/:/p' | sed 's/^/  /'
    echo
    echo "Enumerated devices:"
    local d
    for d in /sys/bus/usb/devices/[0-9]*-[0-9]*; do
        [[ -f "${d}/product" ]] || continue
        printf '  %-12s %-34s %s\n' "$(basename "${d}")" \
            "$(cat "${d}/product" 2>/dev/null)" \
            "$(cat "${d}/power/runtime_status" 2>/dev/null)"
    done
}

reset_hubs() {
    local h dev busnum devnum node
    for h in "${HUBS[@]}"; do
        dev="/sys/bus/usb/devices/${h}"
        if [[ ! -d "${dev}" ]]; then
            echo "  ${h}: not present — the hub has dropped off the bus entirely"
            continue
        fi
        busnum=$(cat "${dev}/busnum")
        devnum=$(cat "${dev}/devnum")
        node=$(printf '/dev/bus/usb/%03d/%03d' "${busnum}" "${devnum}")
        printf '  resetting %s (%s) ... ' "${h}" "${node}"
        if python3 -c "
import fcntl, sys
with open(sys.argv[1], 'wb') as f:
    fcntl.ioctl(f, 0x5514, 0)   # USBDEVFS_RESET
" "${node}" 2>/dev/null; then
            echo "done"
        else
            echo "FAILED"
        fi
    done
    sleep 3
}

reset_controller() {
    echo "  unbinding ${CONTROLLER} ..."
    printf '%s' "${CONTROLLER}" > /sys/bus/pci/drivers/xhci_hcd/unbind 2>/dev/null ||
        echo "  unbind failed (already unbound?)"
    sleep 3
    echo "  rebinding ${CONTROLLER} ..."
    printf '%s' "${CONTROLLER}" > /sys/bus/pci/drivers/xhci_hcd/bind 2>/dev/null ||
        echo "  bind failed"
    sleep 5
}

# A reset clears the port's disabled flag, so put it back afterwards.
quiesce() {
    [[ -x /usr/local/sbin/usb-port-quiesce.sh ]] && /usr/local/sbin/usb-port-quiesce.sh
}

case "${1:-}" in
    hubs)       echo "Resetting hubs ${HUBS[*]}"; reset_hubs; quiesce; echo; state ;;
    controller) echo "Resetting controller ${CONTROLLER}"; reset_controller; quiesce; echo; state ;;
    state)      state ;;
    *)          echo "usage: $0 hubs|controller|state" >&2; exit 2 ;;
esac
