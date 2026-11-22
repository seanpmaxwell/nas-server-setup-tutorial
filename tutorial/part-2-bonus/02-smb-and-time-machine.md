# Bonus 2: Time Machine backups to the Pi (Samba)

This bonus turns your Pi into a network backup disk for macOS Time Machine. It uses **Samba**, the SMB file server, which macOS supports for network Time Machine backups. The backups go into their own folder on the same encrypted drive you set up in Part 1.

**Requires:** Part 1 finished, and a Mac on the same home network.

**Names used in this bonus** (change them if you like, but keep them consistent):

| Item | Value in this guide |
|---|---|
| Backup folder | `/mnt/storage/timemachine` |
| Samba share name | `TimeMachine` |
| Samba user | `<smb-user>` (e.g. `tmuser`) |

All Pi commands run over SSH.

## Step 1: Check the drive

Time Machine over Samba needs extended attributes, which ext4 supports. The drive from Part 1 is already ext4 and mounted at `/mnt/storage`, so there's nothing to format.

```bash
df -T /mnt/storage
```

**Check:** the `Type` column says `ext4`. If the drive isn't mounted, unlock it first (`unlock-storage`).

## Step 2: Install Samba and Avahi

Avahi lets the Mac find the Pi on the network automatically.

```bash
sudo apt update
sudo apt install samba avahi-daemon
```

**Check:** `systemctl is-active smbd avahi-daemon` prints `active` twice.

## Step 3: Make Samba wait for the drive

Like Docker in Part 1, Samba must never start against an empty `/mnt/storage` folder. If it did, a Time Machine backup could start filling the microSD card.

```bash
sudo mkdir -p /etc/systemd/system/smbd.service.d
printf '[Unit]\nRequiresMountsFor=/mnt/storage\n' | sudo tee /etc/systemd/system/smbd.service.d/wait-for-storage.conf
sudo systemctl daemon-reload
sudo systemctl restart smbd
```

**Check:** `systemctl show smbd -p RequiresMountsFor` prints `RequiresMountsFor=/mnt/storage`, and `systemctl is-active smbd` prints `active`.

> **Using manual unlock (chapter 3) instead of automatic unlock (chapter 6)?** At boot, Samba now waits for a drive that's still locked, so it stays off. After running `unlock-storage`, also run `sudo systemctl start smbd`, or add that line to the script next to `sudo systemctl start docker`. (This variant hasn't been tested; the automatic-unlock setup has.)

## Step 4: Create the backup user and folder

```bash
sudo adduser --system --no-create-home --group <smb-user>
sudo mkdir -p /mnt/storage/timemachine
sudo chown -R <smb-user>:<smb-user> /mnt/storage/timemachine
sudo smbpasswd -a <smb-user>      # sets the password the Mac will use
```

The user is a "system" user: it has no home folder and can't log in to the Pi. It exists only so Samba knows who owns the backups. Save the Samba password in your password manager.

**Check:** `ls -ld /mnt/storage/timemachine` shows `<smb-user>` as the owner.

## Step 5: Configure Samba

Open the config file:

```bash
sudo nano /etc/samba/smb.conf
```

Add these lines inside the existing `[global]` section:

```ini
   vfs objects = catia fruit streams_xattr
   fruit:metadata = stream
   fruit:model = MacSamba
   fruit:posix_rename = yes
   fruit:veto_appledouble = no
   fruit:nfs_aces = no
   fruit:wipe_intentionally_left_blank_rfork = yes
   fruit:delete_empty_adfiles = yes
   server min protocol = SMB2
```

Add this section at the end of the file:

```ini
[TimeMachine]
   path = /mnt/storage/timemachine
   valid users = <smb-user>
   read only = no
   vfs objects = catia fruit streams_xattr
   fruit:time machine = yes
   fruit:time machine max size = 1T
```

Double-check that `valid users` and `path` exactly match the user and folder you created. A typo in either stops the Mac from connecting.

### Choosing a size limit

`fruit:time machine max size` caps how much space Time Machine can use. Without it, Time Machine keeps adding backups until the drive is full, and **this drive also holds Nextcloud**.

- Aim for about 1.5–2× the space used on your Mac. A larger limit keeps more backup history.
- Leave plenty of room for Nextcloud and its backups. Check free space with `df -h /mnt/storage`.

The Pi reports this limit to the Mac as the disk's size, so you don't need a separate limit on the Mac.

## Step 6: Check the config and restart

```bash
testparm -s
sudo systemctl restart smbd avahi-daemon
sudo systemctl enable smbd avahi-daemon
```

`testparm` reads `smb.conf`, reports syntax errors and warnings, and prints the configuration Samba will use. It doesn't change anything, so it's safe to run any time. Run it after every edit, before restarting `smbd`.

**Check:** `testparm -s` shows a `[TimeMachine]` section with your path and user, and no errors.

## Step 7: Add the backup disk on the Mac

1. Open **System Settings → General → Time Machine → Add Backup Disk**.
2. Choose **TimeMachine on `<hostname>`**.
3. Log in as `<smb-user>` with the Samba password.
4. Optional: turn on **Encrypt Backup**. The Pi's drive is already encrypted, but this also protects the backup from anyone with access to the unlocked Pi.

The first backup copies everything and can take hours, so connect the Mac by Ethernet if you can. Later backups copy only changes and are much faster.

**Check:** once the first backup finishes, test a restore. Open a folder in Finder, click the Time Machine icon in the menu bar, and choose **Browse Time Machine Backups**.

## Tips

- **Changing the size limit:** edit `fruit:time machine max size` in `smb.conf`, run `testparm -s`, then `sudo systemctl restart smbd`.
- **Use Samba, not AFP/Netatalk.** Apple has deprecated AFP. SMB is the supported way to do network Time Machine backups.
- **Restarts:** restarting `smbd` interrupts a running backup. Time Machine retries on its own later.

## Troubleshooting

If the Mac shows *"There was an error connecting to the selected network backup disk"* or *"There was a problem connecting to the server"*, work through these checks.

### 1. Find where it fails

In Finder, press **⌘K** and connect to `smb://<hostname>.local` (no share name). Log in as `<smb-user>`.

| What happens | Likely cause |
|---|---|
| Login fails | Wrong username or password, or the Samba user isn't set up |
| `TimeMachine` isn't in the list | The share didn't load. Check `testparm -s` and restart `smbd` |
| `TimeMachine` is listed but won't open | A typo in `valid users` or `path`, or folder permissions |

### 2. Test on the Pi

```bash
smbclient -L localhost -U <smb-user>
smbclient //localhost/TimeMachine -U <smb-user> -c 'ls'
sudo -u <smb-user> touch /mnt/storage/timemachine/test && echo OK
ls -ld /mnt/storage /mnt/storage/timemachine
```

| Result | Fix |
|---|---|
| `NT_STATUS_LOGON_FAILURE` | `sudo smbpasswd -a <smb-user>`, then `sudo smbpasswd -e <smb-user>` |
| `NT_STATUS_BAD_NETWORK_NAME` | Fix the `path =` line, or create the folder |
| `NT_STATUS_ACCESS_DENIED`, or `touch` fails | `sudo chown -R <smb-user>:<smb-user> /mnt/storage/timemachine` and `sudo chmod o+x /mnt/storage` |
| `smbd` isn't running after a restart | The drive didn't mount (Step 3 keeps Samba off then). Check `df -h /mnt/storage`, then `sudo systemctl start smbd` |

### 3. Disconnect other connections from the Mac

If Finder is already connected to the Pi over SMB as a different user, Time Machine can't log in as `<smb-user>`.

- Eject the Pi's shares in Finder's sidebar.
- Delete saved entries for the Pi in **Keychain Access**.
- Run `mount | grep smbfs` in Terminal on the Mac to confirm that no SMB connections remain.

An open SSH session to the Pi doesn't matter. SSH and SMB are separate services.

### 4. Watch the Samba log

Run this on the Pi while you retry from the Mac:

```bash
sudo journalctl -u smbd -f
```

For more detail, temporarily add `log level = 3` under `[global]`, restart `smbd`, and check `/var/log/samba/`. Remove the line when you're done.
