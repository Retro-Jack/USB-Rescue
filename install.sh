#!/usr/bin/env bash
#
# install.sh — put usb-rescue in place. Run with sudo.
#
#     sudo ./install.sh              everything
#     sudo ./install.sh watchdog     the watchdog alone
#     sudo ./install.sh --uninstall  take it all out again
#
# The rescue page is a user service and is installed for the user who invoked
# sudo, since it needs their session and their token.
#
set -euo pipefail
cd "$(dirname "$(realpath "$0")")"

USER_NAME="${SUDO_USER:-${USER}}"
USER_HOME=$(getent passwd "${USER_NAME}" | cut -d: -f6)
WHAT="${1:-all}"

if [[ "${WHAT}" == "--uninstall" ]]; then
    systemctl disable --now usb-hc-watchdog.service usb-port-quiesce.service 2>/dev/null || true
    rm -f /etc/systemd/system/usb-hc-watchdog.service /etc/systemd/system/usb-port-quiesce.service
    rm -f /usr/local/sbin/usb-{reset-chain,hc-watchdog,port-quiesce}.sh
    rm -f /etc/sudoers.d/usb-rescue
    systemctl daemon-reload
    sudo -u "${USER_NAME}" systemctl --user disable --now usb-rescue-web.service 2>/dev/null || true
    rm -f "${USER_HOME}/.config/systemd/user/usb-rescue-web.service"
    rm -f "${USER_HOME}/bin/usb-"{lockup-report,port-map}.sh "${USER_HOME}/bin/usb-rescue-web.py"
    echo "removed (｜/etc/usb-rescue.conf left in place)"
    exit 0
fi

[[ -e /etc/usb-rescue.conf ]] || { install -m644 usb-rescue.conf.example /etc/usb-rescue.conf
    echo "wrote /etc/usb-rescue.conf — EDIT IT: the defaults describe one particular machine"; }

install -m755 bin/usb-reset-chain.sh bin/usb-hc-watchdog.sh bin/usb-port-quiesce.sh /usr/local/sbin/

if [[ "${WHAT}" == "all" || "${WHAT}" == "watchdog" ]]; then
    install -m644 systemd/usb-hc-watchdog.service /etc/systemd/system/
    systemctl daemon-reload
    systemctl enable --now usb-hc-watchdog.service
    echo "watchdog running"
fi

if [[ "${WHAT}" == "all" ]]; then
    install -m644 systemd/usb-port-quiesce.service /etc/systemd/system/
    install -d -o "${USER_NAME}" "${USER_HOME}/bin" "${USER_HOME}/.config/systemd/user"
    install -m755 -o "${USER_NAME}" bin/usb-lockup-report.sh bin/usb-port-map.sh bin/usb-rescue-web.py "${USER_HOME}/bin/"
    install -m644 -o "${USER_NAME}" systemd/usb-rescue-web.service "${USER_HOME}/.config/systemd/user/"
    sed "s/YOURUSER/${USER_NAME}/" examples/usb-rescue.sudoers > /tmp/usb-rescue.sudoers
    visudo -cf /tmp/usb-rescue.sudoers >/dev/null
    install -m440 /tmp/usb-rescue.sudoers /etc/sudoers.d/usb-rescue
    rm -f /tmp/usb-rescue.sudoers
    systemctl daemon-reload
    sudo -u "${USER_NAME}" XDG_RUNTIME_DIR="/run/user/$(id -u "${USER_NAME}")" \
        systemctl --user enable --now usb-rescue-web.service 2>/dev/null ||
        echo "start the page yourself: systemctl --user enable --now usb-rescue-web"
    echo
    echo "Firewall the page to your own network, e.g.:"
    echo "  ufw allow from 192.168.0.0/24 to any port 8777 proto tcp"
fi
