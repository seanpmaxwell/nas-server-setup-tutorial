# 3. Encrypted storage (LUKS + ext4)

In this chapter you encrypt the external drive, format it and create a one-word command that unlocks it.

> ⚠️ **This permanently erases the external drive.** Confirm your backup before continuing.

## How the drive will unlock

There are two ways to unlock an encrypted drive:

- **Passphrase after every restart.** This is the most secure: the data is unreadable even if someone takes the Pi and the drive together. After a restart, you SSH in and type the passphrase. It works well with a UPS, since restarts are rare.
- **Keyfile on the microSD card (unlocks automatically at boot).** This protects the drive if it's lost or stolen **on its own**, but not if the Pi is taken with it. In exchange, the server can update and restart without you.

This chapter sets up the passphrase, which you need in either case. [Chapter 6](06-maintenance-and-automation.md#step-4-unlock-the-drive-automatically-at-boot-optional) adds the keyfile if you want automatic unlocking. You can decide then.

## Step 1: Identify the drive

Plug the drive into a **blue** USB port, with its power adapter connected. If the desktop shows a pop-up offering to open it, close it.

```bash
lsblk -o NAME,SIZE,FSTYPE,LABEL,MODEL,MOUNTPOINTS
```

- `mmcblk0` is the microSD card. **Never touch it.**
- Your drive is usually `sda`. This guide calls it `/dev/sdX`; replace `X` with your letter. Confirm it by its size and model.

> Drive makers count in decimal terabytes, but Linux counts in binary "tebibytes", so a drive always looks about 9% smaller. For example, a "20TB" drive shows up as about `18.2T`.

**Check:** exactly one disk matches your drive's size and model, and it's not `mmcblk0`.

## Step 2: Partition and encrypt

Run these **one at a time**, and double-check the device name before each one:

```bash
sudo umount /dev/sdX*                       # "not mounted" errors are fine
sudo parted /dev/sdX --script mklabel gpt mkpart storage 0% 100%
sudo apt install cryptsetup -y
sudo cryptsetup luksFormat /dev/sdX1        # type YES in capitals, then set a strong passphrase
```

> ⚠️ **If you lose the passphrase, your data cannot be recovered.** Save it in your password manager before continuing.

**Check:** `lsblk -f /dev/sdX` shows `sdX1` with the type `crypto_LUKS`.

## Step 3: Unlock, format and mount

```bash
sudo cryptsetup open /dev/sdX1 storage
sudo mkfs.ext4 -L storage -m 1 /dev/mapper/storage
sudo mkdir -p /mnt/storage
sudo mount /dev/mapper/storage /mnt/storage
df -h /mnt/storage
```

- `cryptsetup open` unlocks the partition and makes the decrypted version available as `/dev/mapper/storage`.
- `-m 1` reserves only 1% of the space for the system instead of the default 5%. On large drives this saves hundreds of gigabytes.

You may hear the drive working for a few hours afterward while ext4 finishes setting up in the background. That's normal.

**Check:** `df -h /mnt/storage` shows `/dev/mapper/storage` with roughly your drive's size.

## Step 4: Find the partition's UUID

```bash
sudo cryptsetup luksUUID /dev/sdX1
```

This prints a UUID such as `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`. That's `<luks-uuid>`. Save it in your notes.

**Why:** the name `sdX` can change if you plug in other drives, but the UUID never changes. The rest of the guide uses `/dev/disk/by-uuid/<luks-uuid>` to find the drive reliably.

## Step 5: Back up the LUKS header

The header is a small area at the start of the partition that holds the encryption metadata. If it's damaged, your passphrase alone can't unlock the drive. Keep a copy somewhere else. The copy is still protected by your passphrase.

```bash
sudo cryptsetup luksHeaderBackup /dev/disk/by-uuid/<luks-uuid> --header-backup-file ~/luks-header-backup.img
sudo chown "$USER":"$USER" ~/luks-header-backup.img
```

The `chown` gives the file to your user. `cryptsetup` creates it as root-only, which would block the copy in the next step.

Copy it to another computer. **Run this on your computer, not on the Pi:**

```bash
# macOS / Linux
scp <username>@<pi-lan-ip>:~/luks-header-backup.img ~/Desktop/
```

```powershell
# Windows PowerShell
scp <username>@<pi-lan-ip>:~/luks-header-backup.img "$env:USERPROFILE\Desktop\"
```

**Check:** the file on your computer is about 16MB. Store it somewhere safe, such as a password manager attachment or an encrypted folder, and keep a second copy. Then delete it from the Pi:

```bash
rm ~/luks-header-backup.img
```

> 🔒 The header backup plus your passphrase can unlock the drive. Protect it like the passphrase itself.

## Step 6: Create an `unlock-storage` command

First, add the drive to `/etc/fstab`, the list of filesystems the system knows how to mount:

```bash
echo '/dev/mapper/storage  /mnt/storage  ext4  defaults,noauto,nofail  0  2' | sudo tee -a /etc/fstab
sudo systemctl daemon-reload
```

- `noauto` skips the drive at boot, because it's still locked then.
- `nofail` means boot never hangs waiting for it.

Next, create the script. Paste the whole block at once. The final `EOF` must be on its own line, with nothing after it (no semicolon):

```bash
sudo tee /usr/local/bin/unlock-storage > /dev/null << 'EOF'
#!/bin/bash
set -e
if [ ! -e /dev/mapper/storage ]; then
  sudo cryptsetup open /dev/disk/by-uuid/<luks-uuid> storage
fi
if ! mountpoint -q /mnt/storage; then
  sudo mount /mnt/storage
fi
echo "Storage is unlocked and mounted at /mnt/storage"
EOF
sudo chmod +x /usr/local/bin/unlock-storage
```

The script skips any step that's already done, so it's safe to run any time.

**Check:** restart and test it:

```bash
sudo reboot
```

SSH back in, then:

```bash
unlock-storage
df -h /mnt/storage
```

You're asked for the passphrase, then see `Storage is unlocked and mounted at /mnt/storage`. `df` shows the drive.

## Troubleshooting

| Problem | Fix |
|---|---|
| You're stuck at a `>` prompt while pasting a block | The closing `EOF` wasn't on its own line. Press **Ctrl + C** and paste again. |
| `luksFormat` says the device is in use | A desktop auto-mount grabbed it. Run `sudo umount /dev/sdX*` again, then retry. |
| `unlock-storage: No such file or directory` for the UUID | You left `<luks-uuid>` in the script. Edit it with `sudo nano /usr/local/bin/unlock-storage`. |
| `mount: /mnt/storage: can't find in /etc/fstab` | The fstab line is missing. Check it with `grep storage /etc/fstab`. |
| `scp` says permission denied for the header file | You skipped the `chown` line. Run it, then copy again. |
