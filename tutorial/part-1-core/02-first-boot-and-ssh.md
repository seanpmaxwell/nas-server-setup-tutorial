# 2. First boot and SSH

In this chapter you boot the Pi, update it, move it to Ethernet, and connect to it from your computer over SSH. After this, the Pi doesn't need a monitor.

## Step 1: First boot

1. Insert the microSD card. The slot is on the underside of the Pi, and the card's label faces away from the board.
2. Connect the monitor to the micro-HDMI port **next to the USB-C power port** (HDMI0).
3. Connect a keyboard and mouse. USB ones go in the **black** USB 2 ports; save the **blue** USB 3 ports for the hard drive. Bluetooth ones pair from the desktop's Bluetooth menu.
4. **Leave the external drive unplugged** for now.
5. **Connect power last.** The first boot can take several minutes and may restart once or twice. Don't unplug it during this time.

**Check:** you reach the Raspberry Pi desktop.

## Step 2: Check the fan

Open a Terminal (**Ctrl + Alt + T**):

```bash
vcgencmd measure_temp
cat /sys/class/hwmon/hwmon*/fan1_input
```

The first command shows the temperature and the second shows the fan speed in RPM. A reading of `0` RPM is normal below about 50°C. To force the fan on for a test (note the lowercase **L** in `dl`):

```bash
pinctrl FAN_PWM op dl     # fan to full speed: you should hear it
cat /sys/class/hwmon/hwmon*/fan1_input
pinctrl FAN_PWM a0        # back to automatic (that's a zero)
```

**Check:** the RPM reading is well above `0` while the fan is forced on.

## Step 3: Update the system

```bash
sudo apt update
sudo apt full-upgrade -y
sudo reboot
```

**Why:** you start with the latest security fixes before putting anything on the network.

## Step 4: Switch to Ethernet and find the Pi's address

Connect the Pi to your router (or a mesh point) with an Ethernet cable, then run:

```bash
hostname -I              # all of the Pi's IP addresses
ip -4 addr show eth0     # the wired address specifically
```

**Check:** `eth0` shows an `inet` line with an address, for example `inet 192.168.1.50/24`. That address (without `/24`) is `<pi-lan-ip>`.

> Use Ethernet for the server even if Wi-Fi works on the Pi. Some home networks won't let your computer reach the Pi over Wi-Fi at all. SSH may not work until the Pi is wired (see Troubleshooting).

## Step 5: Connect over SSH from your computer

On **your computer**, open a terminal (Terminal on macOS, PowerShell on Windows):

```bash
ssh <username>@<pi-lan-ip>
```

Type `yes` at the fingerprint question, then your Pi password. In Windows PowerShell or Terminal, **right-click pastes**.

**Check:** the prompt changes to `<username>@<hostname>`. From now on, the rest of the guide runs over SSH.

## Step 6: Reserve the Pi's IP address

In your router's settings or app, find **DHCP reservations** (sometimes called "static leases" or "fixed IP") and reserve the Pi's current wired address.

**Why:** without a reservation, the router may give the Pi a different address after a restart, and your SSH command stops working.

## Step 7: Turn off the Pi's Wi-Fi (once wired)

```bash
sudo nmcli radio wifi off
```

**Check:** `nmcli radio wifi` prints `disabled`, and your SSH session (over Ethernet) is still connected. Chapter 7 shows how to turn Wi-Fi off permanently at the hardware level.

## Optional: remote desktop (VNC)

You don't need this for the rest of the guide, but it gives you a graphical desktop without a monitor:

1. On the Pi: `sudo raspi-config` → **Interface Options → VNC → Yes**. Or use **Preferences → Raspberry Pi Configuration → Interfaces** on the desktop.
2. On your computer, install **TigerVNC Viewer** and connect to `<pi-lan-ip>`.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `Could not resolve hostname <hostname>.local` | Windows often can't resolve `.local` names | Use the IP address instead |
| `Connection refused` | The SSH server isn't running | On the Pi: `sudo systemctl enable --now ssh` |
| `Connection timed out` or `No route to host` | The devices can't see each other on the network | See below |
| SSH over Wi-Fi never works, even though the Pi has a Wi-Fi address | The Wi-Fi network isolates devices from each other | Connect the Pi by Ethernet and use its wired address |

**If your computer and the Pi can't reach each other:**

- Turn off any **VPN** on your computer.
- Make sure both devices are on your **main** network, not a **guest network**. Guest networks isolate devices. A tell-tale sign is the Pi and your computer having addresses in different ranges, such as `192.168.1.x` and `192.168.2.x`.
- Wired devices usually land on the main network automatically, so connecting the Pi by Ethernet often fixes this.
- On the Pi, `ping -c 4 <router-ip>` should work. If it does, but pinging your computer fails, the network is isolating them.
