# 6. Maintenance and automation

In this chapter you set up backups and learn the restart routine. Optionally, you then make the server update, restart and come back online by itself.

The chapter has two paths:

- **Manual unlock (from chapter 3):** after any restart, you SSH in and run `unlock-storage`. Steps 1–3 and 5 apply.
- **Automatic unlock (Step 4):** a keyfile unlocks the drive at boot, so the server can apply updates and restart without you. All steps apply.

## Step 1: The restart routine (manual unlock)

After any restart, such as a power outage or an OS update:

```bash
ssh <username>@<hostname>        # or <pi-tailscale-ip>
unlock-storage
```

Then open the AIO page (`https://<pi-tailscale-ip>:8080`) and click **Start containers** if they aren't already running.

**Check:** `https://<hostname>.<tailnet>` loads Nextcloud.

### Safe shutdown (for example, to move the server)

1. AIO page → **Stop containers**, and wait until they've all stopped.
2. `sudo shutdown -h now`, then wait until the green LED stops flickering.
3. Unplug the Pi, then the drive.

To bring it back up: connect the UPS, Ethernet and drive, power on the drive, then plug in the Pi **last**. Then follow the restart routine (or, with automatic unlock, just wait about 5 minutes). No monitor is needed.

## Step 2: Automatic Nextcloud backups and updates

On the AIO page, go to **Backup and restore**:

1. Set a backup location, for example `/mnt/storage/aio-backups`, and create the first backup.
2. **Save the backup encryption password** (under "reveal all backup options"). You can't restore without it.
3. Enable **Daily backup and automatic updates**. The time is in **UTC**. Nextcloud goes offline briefly during the backup, so pick a quiet hour.

**Check:** the AIO page lists your first backup as successful.

> A backup on the same drive protects you from bad updates and accidental deletions, **not** from the drive failing. Also keep an off-site or second-drive copy. This is the most important item on the [security priorities list](07-security-and-hardening.md#security-priorities).

## Step 3: Cron basics

Cron runs commands on a schedule. Each user has their own list of jobs, called a "crontab". System tasks like updates and restarts belong in **root's** crontab.

```bash
crontab -e          # edit your own jobs
sudo crontab -e     # edit root's jobs
sudo crontab -l     # list root's jobs
```

The first time, you're asked to pick an editor. `nano` is the easiest. Save with **Ctrl + O**, **Enter**, then exit with **Ctrl + X**.

```
* * * * * command
│ │ │ │ └─ day of week (0–7, 0 and 7 = Sunday)
│ │ │ └─── month (1–12)
│ │ └───── day of month (1–31)
│ └─────── hour (0–23)
└───────── minute (0–59)
```

| Schedule | Value |
|---|---|
| Every Sunday at 2am | `0 2 * * 0` |
| Every day at 3:30am | `30 3 * * *` |
| Every 15 minutes | `*/15 * * * *` |
| Once at every boot | `@reboot` |

Tips to avoid common problems:

- **Use full paths.** Cron runs with a minimal `PATH`. Run `which <command>` to find a command's full path.
- **Make scripts executable** with `chmod +x`, and start them with `#!/bin/bash`.
- **Log the output** by adding `>> /var/log/myjob.log 2>&1`. Otherwise errors disappear silently.
- **Check a schedule** at crontab.guru.
- **Check the time zone.** Cron uses the system clock. Run `date` to see it, and `sudo raspi-config` → **Localisation Options** to change it. Use a city-based IANA name such as `<Region/City>` (for example `Europe/Berlin`), not an abbreviation like `CET`. Abbreviations only cover half the year, so the clock would be an hour off after the daylight-saving change.

## Step 4: Unlock the drive automatically at boot (optional)

With a manual passphrase, automatic restarts are impossible: the server would come back with a locked drive. A **keyfile** (a small random file stored on the Pi) can unlock the drive at boot instead.

### Understand the trade-off first

| Threat | Protected? |
|---|---|
| Someone steals only the drive | ✅ Yes |
| The drive fails and you send it for warranty or throw it away | ✅ Yes |
| Someone steals the Pi and the drive together | ❌ No. The keyfile is on the unencrypted microSD card. |

If you need protection against the last case too, look into **Clevis + Tang** (network-bound disk encryption). It isn't covered here. With it, the drive unlocks only while the Pi can reach another device on your home network.

Your passphrase keeps working either way. The keyfile goes into a spare LUKS key slot.

### 4a. Back up the LUKS header again

You're about to change the drive's key slots, so take a fresh header backup first. Repeat [chapter 3, Step 5](03-encrypted-storage.md#step-5-back-up-the-luks-header): create it, copy it to your computer, then delete it from the Pi.

### 4b. Create the keyfile

```bash
sudo dd if=/dev/urandom of=/root/.storage.key bs=512 count=8
sudo chmod 400 /root/.storage.key
```

This creates 4KB of random data that only root can read.

### 4c. Add the keyfile to the drive

```bash
sudo cryptsetup luksAddKey /dev/disk/by-uuid/<luks-uuid> /root/.storage.key
```

You're asked for your existing passphrase. Then test the keyfile:

```bash
sudo cryptsetup open --test-passphrase --key-file /root/.storage.key /dev/disk/by-uuid/<luks-uuid> && echo "Keyfile OK"
```

**Check:** you see `Keyfile OK`. **Don't continue until you do.**

### 4d. Tell the system to unlock and mount at boot

Two files control this:

- `/etc/crypttab` lists encrypted devices to unlock at boot.
- `/etc/fstab` lists filesystems to mount at boot.

First, make sure the boot-time unlock tool is installed. Newer Debian releases ship it as a separate package:

```bash
ls /usr/lib/systemd/system-generators/ | grep cryptsetup || sudo apt install -y systemd-cryptsetup
```

Add the drive to `crypttab`:

```bash
echo 'storage  UUID=<luks-uuid>  /root/.storage.key  luks,nofail' | sudo tee -a /etc/crypttab
```

`nofail` means the Pi still boots normally if the drive is unplugged or fails to unlock.

Now remove `noauto` from the fstab line you added in chapter 3, so the drive mounts at boot. This keeps a backup copy of the file first:

```bash
sudo cp /etc/fstab /etc/fstab.bak
sudo sed -i '/^\/dev\/mapper\/storage/s/noauto,//' /etc/fstab
grep storage /etc/fstab
```

**Check:** the line is now exactly:

```
/dev/mapper/storage  /mnt/storage  ext4  defaults,nofail  0  2
```

### 4e. Start Docker at boot, but only after the drive is mounted

In chapter 5 Docker was disabled at boot, with a safety net. Now it should start at boot, but only once the drive is mounted. Add `RequiresMountsFor` to the same override file:

```bash
printf '[Unit]\nConditionPathIsMountPoint=/mnt/storage\nRequiresMountsFor=/mnt/storage\n' | sudo tee /etc/systemd/system/docker.service.d/wait-for-storage.conf
sudo systemctl daemon-reload
sudo systemctl enable docker
```

- `RequiresMountsFor` makes Docker wait for the drive, and stay off if the drive fails to unlock.
- `ConditionPathIsMountPoint` (from chapter 5) is a second check that skips starting Docker if `/mnt/storage` isn't a real mount.

Without this, Nextcloud might start against an empty `/mnt/storage` folder and write to the microSD card, or act as if your data is gone.

**Check:** `systemctl show docker -p RequiresMountsFor` prints `RequiresMountsFor=/mnt/storage`.

Keep `unlock-storage` as a fallback. If the keyfile ever stops working, it unlocks with your passphrase.

## Step 5: A weekly update script

Save this as `/usr/local/sbin/routine-update.sh` (for example with `sudo nano /usr/local/sbin/routine-update.sh`):

```bash
#!/bin/bash
# Routine system update. Run as root: sudo /usr/local/sbin/routine-update.sh
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Please run with sudo." >&2
  exit 1
fi

# Never stop to ask questions; keep existing config files when packages update them
export DEBIAN_FRONTEND=noninteractive
APT_OPTS=(-y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold)

echo "=== Update started: $(date) ==="

apt-get update
apt-get full-upgrade "${APT_OPTS[@]}"
apt-get autoremove --purge -y
apt-get clean

if [ -f /var/run/reboot-required ]; then
  echo "Restart needed. Rebooting now; storage will unlock automatically."
  echo "=== Update finished: $(date) ==="
  systemctl reboot
else
  echo "No restart needed."
  echo "=== Update finished: $(date) ==="
fi
```

Most updates don't need a restart. Debian creates `/var/run/reboot-required` when one does, such as after a kernel update, and the script restarts the Pi only then.

> ⚠️ **Using manual unlock?** Don't let the script restart the Pi, or the drive stays locked and Nextcloud stays down until you notice. Replace the `if … fi` block at the end with:
>
> ```bash
> if [ -f /var/run/reboot-required ]; then
>   echo "NOTE: A restart is needed to finish updates."
>   echo "After restarting, SSH in and run: unlock-storage"
> fi
> echo "=== Update finished: $(date) ==="
> ```

```bash
sudo chmod +x /usr/local/sbin/routine-update.sh
sudo /usr/local/sbin/routine-update.sh
```

**Check:** the test run ends with `=== Update finished: … ===`.

Optional extra: also turn on automatic security updates between the weekly runs:

```bash
sudo apt install unattended-upgrades -y && sudo dpkg-reconfigure -plow unattended-upgrades
```

## Step 6: Start Nextcloud's containers automatically after a restart (automatic unlock)

After a restart, the AIO master container comes back by itself, but the other containers (Nextcloud itself, the database and so on) often stay stopped until you click **Start containers**. AIO has a built-in command that does the same as that button. The script below waits for the master container, runs that command, then logs a status summary.

Save it as `/usr/local/sbin/start-nextcloud.sh`:

```bash
#!/bin/bash
# Runs at boot from root's crontab: starts Nextcloud AIO containers, then logs status.
echo "=== Boot: $(date) ==="

# Wait up to 5 minutes for the AIO master container to be running
for i in $(seq 1 30); do
  [ "$(docker inspect -f '{{.State.Running}}' nextcloud-aio-mastercontainer 2>/dev/null)" = "true" ] && break
  sleep 10
done
sleep 30   # give it a moment to finish starting up

echo "Starting Nextcloud AIO containers..."
docker exec --env START_CONTAINERS=1 nextcloud-aio-mastercontainer /daily-backup.sh

echo "--- Status: $(date) ---"
mountpoint /mnt/storage
systemctl is-active docker
docker ps --format '{{.Names}}: {{.Status}}'
```

```bash
sudo chmod +x /usr/local/sbin/start-nextcloud.sh
```

**Check without restarting:** click **Stop containers** on the AIO page, then run:

```bash
sudo /usr/local/sbin/start-nextcloud.sh
```

After about a minute, all the `nextcloud-aio-*` containers are listed as `Up`.

Because of Step 4e, Docker runs only when the drive is mounted, so this script can never start Nextcloud without your data.

> If you start the command by hand, you may see it written as `docker exec -it …`. The `-it` flags need a terminal you're typing in, so cron can't use them. The script leaves them out.

## Step 7: Schedule it

```bash
sudo crontab -e
```

Add these lines at the bottom:

```
# Every Sunday at 2am: update, and restart if needed
0 2 * * 0 /usr/local/sbin/routine-update.sh >> /var/log/routine-update.log 2>&1

# At every boot: start Nextcloud AIO and log status (automatic unlock only)
@reboot /usr/local/sbin/start-nextcloud.sh >> /var/log/routine-update.log 2>&1
```

With manual unlock, add only the first line.

With automatic unlock, the full weekly cycle now runs on its own:

```
Sunday 2am → update → restart (only if needed) → drive unlocks with the keyfile
→ drive mounts → Docker starts → Nextcloud containers start → status logged
```

## Step 8: Run a restart test (automatic unlock)

Do this once while you're near the Pi, at a time when a short Nextcloud outage is OK:

```bash
sudo reboot
```

Wait about 5 minutes, SSH back in, and check:

```bash
lsblk -f | grep -A1 crypto_LUKS    # "storage" under the partition, mounted at /mnt/storage
mountpoint /mnt/storage            # "/mnt/storage is a mountpoint"
systemctl is-active docker         # "active"
sudo docker ps                     # nextcloud-aio-* containers "Up"
tail -n 20 /var/log/routine-update.log
```

**Check:** every line matches its comment, and the log shows a `=== Boot: … ===` section.

## Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| After a restart, the drive isn't mounted | The keyfile didn't unlock it | Check `sudo journalctl -b -u systemd-cryptsetup@storage`. In the meantime, run `unlock-storage`. |
| Docker is off after a restart | The drive didn't mount (Docker is designed to stay off then) | Fix the mount first. `systemctl status docker` shows the reason. |
| Containers are up but Nextcloud acts as if your data is gone | Docker started before the drive was ready | Make sure Step 4e is done. Stop the containers on the AIO page, check `df -h /mnt/storage`, then start them again. |
| A cron job never runs | A relative path, a missing `chmod +x`, or no logging | Use full paths, make the script executable, and read the `.log` file |
| An "Unlock Keyring" pop-up after a restart | The desktop's password store, unrelated to your drive | Cancel it, or see "Boot to the console" in [chapter 7](07-security-and-hardening.md) |
| `routine-update.sh` stops with a question about a config file | It was run without the options shown | Use the script exactly as shown; `--force-confold` keeps your current config |
