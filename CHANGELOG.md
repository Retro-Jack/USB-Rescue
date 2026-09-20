# Changelog

## [1.0.0] - 20/09/2026

First release, written after the controller at `0000:07:00.3` died on a running
machine and left it with no keyboard or mouse for nearly two hours.

- **usb-hc-watchdog.sh** — watches the kernel log for the controller being
  declared dead and rebinds it, with a two-minute cooldown, a five-per-hour
  ceiling, and a `--test` mode that checks the matching without touching
  hardware.
- **usb-rescue-web.py** — a phone-friendly page on the local network: take a
  report, reset the hubs, reset the controller, start and read a port map.
  Key-protected; the resets go through a `sudoers` rule naming exactly three
  command lines.
- **usb-reset-chain.sh** — the root half: resets the hubs, or unbinds and
  rebinds the controller, and reports what is on the bus afterwards.
- **usb-lockup-report.sh** — read-only evidence dump: kernel log, USB tree,
  enumerated devices, whether keypresses reach the kernel.
- **usb-port-map.sh** — pairs physical sockets with USB port numbers, speaking
  each aloud, and naming the controller each bus belongs to.
- **usb-port-quiesce.sh** — switches off a hub port that cannot enumerate.
- **install.sh** — installs, or removes, the lot; `/etc/usb-rescue.conf` holds
  the controller, hubs, optional dead port and page port.
- **DIAGNOSIS.md** — the failure written up as a case study: three controllers
  with their PCI paths, the hub topology, the kernel messages with timestamps,
  what the evidence rules out, and the ranked next steps.
