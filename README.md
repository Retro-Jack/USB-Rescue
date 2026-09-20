# usb-rescue

Tools for a PC whose USB controller dies while the machine keeps running: the
keyboard and mouse stop responding, the ports still have power, and the only
apparent way out is the power button.

This is what that looks like in the kernel log:

```
xhci_hcd 0000:07:00.3: xHCI host not responding to stop endpoint command
xhci_hcd 0000:07:00.3: xHCI host controller not responding, assume dead
xhci_hcd 0000:07:00.3: HC died; cleaning up
usb 3-6: USB disconnect, device number 3
```

Everything on that controller disconnects at once. The machine itself is fine —
the kernel is running, the disks are working, the network is up — but there is
no way to type at it. **Rebinding the controller brings it all back in about ten
seconds**, so the machine can fix itself, and you can drive the recovery from a
phone when it doesn't.

Written for an AMD X570 board, where this failure is well known, but nothing here
is specific to that: the controller and hubs are configuration, not code.

## What's in it

| | |
|---|---|
| **usb-hc-watchdog.sh** | Watches the kernel log and rebinds the controller the moment it is declared dead. This is the piece that turns a dead afternoon into a hiccup. |
| **usb-rescue-web.py** | A phone-friendly page on your own network: take a report, reset the hubs, reset the controller, map the ports. For when the machine can't fix itself. |
| **usb-reset-chain.sh** | Does the resetting, as root. The page and the watchdog both call it. |
| **usb-lockup-report.sh** | Read-only snapshot while things are broken: kernel log, USB tree, which devices are still enumerated, whether keypresses reach the kernel. Run it *before* rebooting, or the evidence is gone. |
| **usb-port-map.sh** | Tells you which physical socket is which USB port — and speaks each one aloud, since you can't see the screen from behind the case. |
| **usb-port-quiesce.sh** | Optional. Switches off a hub port that can't enumerate, so the kernel stops retrying it at every boot. |

## Install

```sh
git clone https://github.com/Retro-Jack/usb-rescue.git
cd usb-rescue
sudo ./install.sh              # everything
sudo ./install.sh watchdog     # just the watchdog
sudo ./install.sh --uninstall
```

Then **edit `/etc/usb-rescue.conf`** — the shipped defaults describe one
particular machine and will not match yours:

```sh
CONTROLLER="0000:07:00.3"                  # the controller to rebind
HUBS="3-6 3-6.5"                           # hubs to try first, if any
QUIESCE_PORT=""                            # a dead hub port to switch off
WEB_PORT=8777
```

Find your own values with:

```sh
lsusb -t                                   # which bus your keyboard is on
readlink -f /sys/bus/usb/devices/usb3      # that bus's PCI address
```

The rescue page listens on all interfaces, so **firewall it to your own
network**:

```sh
sudo ufw allow from 192.168.0.0/24 to any port 8777 proto tcp
```

## The watchdog

It reads the kernel log, matches the controller's death messages, and runs the
rebind. Guard rails, because a watchdog that acts on its own should be dull and
predictable:

- **One action per failure.** A single death prints three lines; a two-minute
  cooldown keeps that to one rebind.
- **It gives up rather than looping.** More than five deaths in an hour and it
  stops acting and says so in the journal: that is hardware wanting attention,
  not something to paper over every two minutes.
- **It never acts on old news.** It reads only from the moment it starts, so a
  failure recorded in a previous boot can't trigger a rebind at start-up.
- **You can test the matching** without touching any hardware:

```sh
printf 'xhci_hcd 0000:07:00.3: HC died; cleaning up\n' | \
    /usr/local/sbin/usb-hc-watchdog.sh --test
```

Watch it work: `journalctl -u usb-hc-watchdog -f`

## The rescue page

Open it on a phone, press a button. The buttons escalate, and you stop as soon
as typing works again:

1. **Take report** — reads only, saves the evidence.
2. **Reset the hubs** — for when a hub has wedged but the controller is alive.
3. **Reset the controller** — drops every device on it for a few seconds.

Every request must carry a key, generated on first run and kept in
`~/.config/usb-rescue-token`; the address the service prints at startup contains
it, so bookmark that. Wrong key or no key gets a 403. The resets need root, so
`install.sh` adds a `sudoers` rule allowing **exactly** three command lines —
`usb-reset-chain.sh hubs`, `controller` and `state` — and nothing else.

**If the controller is already dead, the hub buttons will do nothing.** That is
correct rather than broken: the hubs were deregistered along with everything
else on that controller, so there is nothing left to reset. Use the controller
button.

## Working out what failed

`usb-lockup-report.sh` writes to `/mnt/misc/lockup-reports/` (or `~/lockup-reports`)
and prints a short verdict. The useful questions it answers:

- **Is the keyboard still enumerated?** If not, the bus lost it.
- **Do keypresses reach the kernel?** Press keys while it runs; 0 bytes with
  nobody typing proves nothing.
- **What did the kernel say?** "HC died" names the controller and the minute.

Two symptoms worth knowing, because they look alarming and aren't:

- **The keyboard's lights stay on** while it is unresponsive. The ports still
  supply power; it is the data path that has gone.
- **The machine still shuts down cleanly** from the power button. The kernel is
  healthy — only USB is gone.

## Requirements

Linux with systemd, Bash 4.4 or later, and Python 3 for the page.
`spd-say` (speech-dispatcher) is optional, used by the port mapper to read
sockets aloud. No other dependencies.

## Licence

MIT — see [LICENSE](LICENSE).
