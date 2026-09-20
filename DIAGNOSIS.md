# The machine, and what actually happened

A record of this specific case, so none of it has to be worked out twice.
This repository is private; the values below are real.

## The machine

| | |
|---|---|
| Host | `thebeast`, CachyOS, kernel 7.2.x |
| Board | Gigabyte **X570S GAMING X**, BIOS **F5** (06/08/2023) |
| Kernel cmdline | includes `nowatchdog` |
| LAN | 192.168.0.107, router 192.168.0.1 |

Three USB controllers, all AMD Matisse `1022:149c`:

| PCI | Buses | Attached via | History |
|---|---|---|---|
| `0000:07:00.1` | 1, 2 | chipset: `00:01.2 → 01:00.0 → 02:08.0` | fine |
| **`0000:07:00.3`** | **3, 4** | chipset: `00:01.2 → 01:00.0 → 02:08.0` | **this is the one that dies** |
| `0000:0c:00.3` | 5, 6 | CPU: `00:08.1` | fine — the external drives live here |

## The topology that matters

Keyboard, mouse and USB headset all hang off **two daisy-chained bus-powered
Terminus FE 2.1 hubs** on one port of the failing controller:

```
bus 3 (0000:07:00.3)
└─ 3-6     Terminus 7-port hub  (bMaxPower 100mA, bus-powered)
   ├─ 3-6.6   Microdia USB Keyboard        (0c45:7603, low-speed)
   └─ 3-6.5   Terminus 7-port hub          (chained into the first)
      ├─ 3-6.5.4  Logitech G300s mouse     (046d:c246)
      └─ 3-6.5.6  C-Media USB headset      (0d8c:0012)
```

It is a **desk hub**, awkward to reach. The card reader (`3-4`) is on the same
controller; the WD external drives (`6-3`, `6-4`) are on the CPU controller and
have never been affected.

## The failure, 20/09/2026

```
14:24:12  xhci_hcd 0000:07:00.3: xHCI host not responding to stop endpoint command
14:24:12  xhci_hcd 0000:07:00.3: xHCI host controller not responding, assume dead
14:24:12  xhci_hcd 0000:07:00.3: HC died; cleaning up
14:24:12  usb 3-4, 3-6, 3-6.5, 3-6.5.4, 3-6.5.6, 3-6.6: USB disconnect
...
16:07:34  controller unbound and rebound from the phone
16:07:38  hubs, keyboard, mouse and headset all back
```

Nothing preceded it: no PCIe AER errors, no warnings, no device resets. The
controller was not in a power-saving state (`power/control` = `on`). It simply
stopped answering, and every device on it went at once.

**The hub buttons did nothing, correctly.** Once the controller is declared
dead the kernel deregisters everything below it, so there were no hubs left to
reset. Only the controller rebind could work — and it did, in about ten seconds.

## What this rules out

- **Not the hubs or their cables.** The controller died above them.
- **Not power.** The keyboard's lights stayed lit throughout; the ports had
  power, the data path was gone.
- **Not the desktop.** The kernel, disks and network were healthy; the power
  button still shut the machine down gracefully.
- **Not autosuspend.** Autosuspend was already pinned off for that whole chain
  (udev rule, 18/09) and the controller still died.

## Earlier findings, still true

- **`3-6.5-port2` cannot enumerate** — "Cannot enable. Maybe the USB cable is
  bad?" ×4, a power cycle, then "unable to enumerate USB device", at **every**
  boot and after every hub reset. Something unidentified is plugged into port 2
  of the inner hub. `usb-port-quiesce.sh` disables that port so the kernel stops
  retrying; the physical cause is still unknown because the hub is out of reach.
- A **hub reset on its own works** when the controller is alive: rehearsed
  18/09, everything came back by itself (keyboard 1.2 s, mouse and headset ~5 s).

## What to try next, in order of effort

1. **Move the keyboard and mouse to the CPU controller** (`0000:0c:00.3`,
   buses 5/6). The drives have been there for days without trouble. Use
   `usb-port-map.sh` to find which rear sockets those are — it speaks each one
   aloud as you plug into it.
2. **The watchdog** (installed 20/09) makes the failure self-healing meanwhile.
3. **BIOS**, the documented AMD fixes for this symptom:
   - *Power Supply Idle Control* → **Typical Current Idle**
   - *Global C-State Control* → **Disabled**
   - a firmware version newer than F5 (Gigabyte's site blocks automated
     fetching, so check it by hand)
4. If it persists on the CPU controller too, a **powered** hub — or no hub at
   all — is the next variable to remove.

## Related bits on this machine

- **SSH**, LAN-only, enabled 18/09: `/etc/ssh/sshd_config.d/10-local-only.conf`
  (AllowUsers jack, no root login), ufw allows 22/tcp from 192.168.0.0/24.
  Password auth is on; there are no authorised keys.
- **The rescue page** runs as a user service with lingering enabled, so it is up
  from boot, before anyone logs in — which matters if a lockup ever leaves you
  at the login screen with a dead keyboard.
- Reports land in `/mnt/misc/lockup-reports/`.
