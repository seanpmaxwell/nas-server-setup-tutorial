# 7. Security and hardening

In this chapter you switch SSH to keys, turn off services the server doesn't need and lock down your Tailscale account. It ends with a secrets checklist and a reference of every file this guide creates.

Do these steps **after** everything else works. Several of them can lock you out if you do them in the wrong order, and each one says how to check before moving on.

## Step 1: Key-based SSH login

With password login, anyone who can reach your SSH port can try to guess your password. With key-based login:

- A **private key** stays on your computer and never leaves it.
- A **public key** goes on the Pi.
- Your computer proves it has the private key without ever sending it, so there's nothing to guess.

**How important is it?** If SSH is open to the internet, it's essential. Here, the Pi is reachable only on your home network and through Tailscale, so it's a good habit rather than an emergency. It still protects you against a compromised device on the same network.

### 1a. Create a key (on your computer)

```bash
ssh-keygen -t ed25519
```

Press **Enter** to accept the default location. Setting a passphrase is recommended, since it protects the key if your computer is stolen. Your operating system can remember it for you.

### 1b. Copy the public key to the Pi (on your computer)

```bash
# macOS / Linux
ssh-copy-id <username>@<hostname>
```

```powershell
# Windows PowerShell
type $env:USERPROFILE\.ssh\id_ed25519.pub | ssh <username>@<hostname> "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
```

### 1c. Test it

```bash
ssh <username>@<hostname>
```

**Check:** it logs you in **without asking for the Pi's password**. It may ask for the key's passphrase, which is different. ⚠️ **Don't continue until this works.**

### 1d. Turn off password login (on the Pi)

> ⚠️ **Lockout risk.** Keep your current SSH session open as a safety net until Step 1e passes.

```bash
printf 'PasswordAuthentication no\nKbdInteractiveAuthentication no\n' | sudo tee /etc/ssh/sshd_config.d/00-keys-only.conf
sudo sshd -t && sudo systemctl restart ssh
```

Why the `00-` at the start of the file name? SSH uses the **first** value it finds for each setting, and it reads the files in that folder in alphabetical order. Some systems include their own file there that turns password login back on. Starting the name with `00-` makes sure yours is read first.

**Check:**

```bash
sudo sshd -T | grep -Ei 'passwordauthentication|kbdinteractive'
```

Both settings say `no`.

### 1e. Confirm from a new terminal

```bash
ssh <username>@<hostname>                                   # should still work with your key
ssh -o PubkeyAuthentication=no <username>@<hostname>        # should fail: "Permission denied (publickey)"
```

**Tip:** set up a key on a second device too, so losing one doesn't mean a trip to the Pi.

### What if I lose my key?

You're not locked out. Turning off password login affects only **SSH**. Plug in a monitor and keyboard and log in at the Pi with your normal password. From there, add a new key, or undo the change:

```bash
sudo rm /etc/ssh/sshd_config.d/00-keys-only.conf
sudo systemctl restart ssh
```

## Step 2: Make the Pi leaner (optional)

### Boot to the console instead of the desktop

When Raspberry Pi OS boots to the desktop, the whole graphical session runs even with no monitor connected. That usually takes **200–500MB of RAM** plus some CPU, which Nextcloud could use instead. It can also cause an **"Unlock Keyring"** pop-up after a restart. That's the desktop's password store, unrelated to your encrypted drive.

See what the desktop is using:

```bash
systemctl get-default                     # graphical.target = boots to the desktop
free -h                                   # total memory in use
ps -eo rss,comm --sort=-rss | head -15    # biggest processes (RSS in KB)
```

If you manage the Pi only over SSH, switch to console boot:

```bash
sudo systemctl set-default multi-user.target
sudo reboot
```

To go back to the desktop, use `sudo systemctl set-default graphical.target` and restart.

> ⚠️ **VNC users:** if your VNC server shares the Pi's own desktop session (chapter 2's setup), console boot removes that session. VNC servers that create their own virtual desktops (like TigerVNC's `vncserver`) aren't affected.

**If you want to keep the desktop** and stop the keyring pop-up: install `seahorse`, open **Passwords and Keys**, right-click the keyring, choose **Change Password**, and set it to blank. The trade-off is that passwords saved in the keyring are then stored unencrypted on the microSD card.

### Turn off Bluetooth

> ⚠️ **Using a Bluetooth keyboard or mouse with the Pi?** They stop working after this. Do it only once you manage the Pi entirely over SSH, or keep a USB keyboard handy for emergencies (like the lost-SSH-key case above).

Turning off Bluetooth frees only about 5–15MB, but it's good hardening on a server that doesn't use it. Bluetooth has had serious bugs that let nearby attackers take over devices without pairing. The risk is low, since an attacker has to be within about 10–30 meters, but a service that isn't running can't be attacked at all.

```bash
echo 'dtoverlay=disable-bt' | sudo tee -a /boot/firmware/config.txt
sudo systemctl disable --now bluetooth
sudo reboot
```

**Check:** `bluetoothctl show` reports no controller.

To undo it, delete the `dtoverlay=disable-bt` line from `/boot/firmware/config.txt`, run `sudo systemctl enable bluetooth`, and restart.

### Turn off Wi-Fi at the hardware level

Chapter 2 turned Wi-Fi off with `nmcli`. To disable the Wi-Fi chip entirely, add `dtoverlay=disable-wifi` to `/boot/firmware/config.txt` the same way, then restart.

> ⚠️ Don't do this while you're connected over Wi-Fi, or you'll lose your SSH connection after the restart.

## Step 3: Check that nothing is unintentionally public

```bash
tailscale funnel status    # Funnel makes services PUBLIC. It should be off unless you meant it.
tailscale serve status     # Serve shares only within your tailnet, which is fine.
```

Also check your router's port-forwarding page to confirm that nothing points at the Pi.

**Check:** `serve status` shows only `(tailnet only)` entries.

## Step 4: Public share links with Tailscale Funnel (optional)

Nextcloud share links work only for people on your tailnet. To send a link to anyone, you can turn on **Funnel**, which makes Nextcloud public on the internet:

```bash
sudo tailscale funnel --bg http://127.0.0.1:11000   # make it public
tailscale funnel status                              # shows "(Funnel on)"
```

To make it private again:

```bash
sudo tailscale funnel --https=443 off
sudo tailscale serve --bg http://127.0.0.1:11000
```

> ⚠️ Use the commands above to turn Funnel off. `tailscale funnel reset` and `tailscale serve reset` remove **every** Serve entry, including any you add in the bonuses.

Then, in Nextcloud, open a file → **Share** → **Share link**, and set a **password** and an **expiration date**. Send the link and the password through different channels.

**While Funnel is on, your login page is public.** Your `.ts.net` name appears in public certificate logs, so bots will find it. So:

- Use strong passwords and 2FA on **every** account
- Keep Nextcloud updated (chapter 6, Step 2)
- Check **Administration settings → Overview** for warnings, and run **scan.nextcloud.com**
- Review and delete old share links

SSH and the AIO admin page (port 8080) stay private either way.

> The [custom domain bonus](../part-2-bonus/01-custom-domain.md) is an alternative to Funnel: Nextcloud becomes public on your own domain through a cloud proxy. If you set that up, keep Funnel off.

## Step 5: Protect your Tailscale account

Your Tailscale login now guards access to your Pi. If someone took over the account you sign in with, they could add their own devices to your tailnet. They'd still face your Nextcloud, SSH and AIO passwords, but you can close this gap:

- Use a strong password and two-factor login on the account you sign in with (Google, Microsoft, Apple, GitHub and so on). A passkey or hardware security key is best.
- Remove old devices from the Machines page.
- Optionally, enable **Tailnet Lock** (admin console → **Settings**). New devices must then be signed by one of your existing trusted devices. Store its recovery keys safely.

By default, every device on a tailnet can reach every port on every other device. That's fine while the tailnet holds only your own devices. If you add an internet-facing server (as in the custom domain bonus), restrict what it can reach with Tailscale access controls. [Bonus 1, Part 7](../part-2-bonus/01-custom-domain.md#part-7-lock-down-the-proxy) shows how.

## Step 6: Privacy between users

The server admin **can technically access** other users' files, either by resetting their password or by reading the data on disk while it's unlocked. Tell other users this. For truly private files, they should use one of these:

- **Nextcloud end-to-end encryption.** As admin, enable the **End-to-End Encryption** app. The user then clicks **Set up encryption** in the desktop or mobile client, saves the mnemonic, creates an **empty** folder, and right-clicks it → **Encrypt**. Encrypted folders can't be edited in the browser and **can't be shared by public link**.
- **Cryptomator,** which encrypts a folder on the user's device before it syncs.

## Secrets checklist

Keep all of these in a password manager:

- [ ] Pi user password
- [ ] LUKS passphrase, plus the header backup file
- [ ] AIO admin passphrase
- [ ] Nextcloud admin password, plus 2FA backup codes
- [ ] AIO backup (Borg) encryption password
- [ ] End-to-end encryption mnemonic (per user)
- [ ] Tailnet Lock recovery keys
- [ ] SSH private key passphrase (and a second device with its own key)

The keyfile `/root/.storage.key` (chapter 6) doesn't need a copy, since your passphrase still works. Never put it next to the header backup.

## Security priorities

If you only have time for some of this, here's a sensible order:

1. **Backups.** Set up AIO's built-in backups (chapter 6, Step 2) to a second drive or an off-site copy. Encryption protects against theft, not against drive failure or accidental deletion.
2. **Secure your Tailscale account** with two-factor login, and remove old devices (Step 5).
3. **If you expose anything publicly** (Funnel or the custom domain bonus), use strong passwords and 2FA everywhere, and limit what a public-facing proxy can reach.
4. **Automatic updates** (chapter 6).
5. **Key-based SSH** (Step 1).
6. **Turn off unused services** such as Bluetooth and the desktop (Step 2).

## Quick reference: files this guide creates

| File | Purpose | Chapter |
|---|---|---|
| `/etc/fstab` (one line) | Mounts the drive at `/mnt/storage` | 3, 6 |
| `/usr/local/bin/unlock-storage` | Unlocks with your passphrase, mounts and starts Docker | 3, 5 |
| `/etc/docker/daemon.json` | Docker's data on the drive; Tailscale DNS | 5 |
| `/etc/systemd/system/docker.service.d/wait-for-storage.conf` | Docker only runs when the drive is mounted | 5, 6 |
| `/root/.storage.key` | Keyfile that unlocks the drive at boot | 6 |
| `/etc/crypttab` | Unlocks the drive at boot | 6 |
| `/usr/local/sbin/routine-update.sh` | Weekly update; restarts only if needed | 6 |
| `/usr/local/sbin/start-nextcloud.sh` | Starts Nextcloud AIO containers at boot | 6 |
| `/var/log/routine-update.log` | Log for updates and boot checks | 6 |
| `/etc/ssh/sshd_config.d/00-keys-only.conf` | Turns off SSH password login | 7 |

## Troubleshooting

| Problem | Fix |
|---|---|
| After Step 1d, SSH says `Permission denied (publickey)` from your own computer | Your key isn't on the Pi. Use the session you kept open (or a monitor and keyboard) to fix `~/.ssh/authorized_keys`, or remove `00-keys-only.conf`. |
| `sshd -T` still shows `passwordauthentication yes` | Another file in `/etc/ssh/sshd_config.d/` sorts before yours. Check `ls /etc/ssh/sshd_config.d/`. |
| VNC shows a black screen after console boot | Your VNC server shared the desktop session. Switch back to `graphical.target`, or use a virtual-desktop VNC server. |
| Nextcloud stopped loading after turning Funnel off | The Serve entry was removed. Run `sudo tailscale serve --bg http://127.0.0.1:11000`. |
| Bluetooth keyboard stopped working | Expected after Step 2. Undo it as described, or use a USB keyboard. |
