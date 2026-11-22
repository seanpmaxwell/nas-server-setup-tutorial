# 5. Docker and Nextcloud All-in-One

In this chapter you install Docker, run Nextcloud All-in-One (AIO) and publish it to your devices through Tailscale.

**Design choice:** Docker's data, including Nextcloud's database, lives **on the encrypted drive**. That keeps everything encrypted and slows down microSD wear. It also means Docker **can't run until the drive is unlocked**, which is exactly what we want.

## Step 1: Install Docker

Make sure the drive is unlocked. Running `df -h /mnt/storage` should show the drive; if not, run `unlock-storage`. Then:

```bash
curl -fsSL https://get.docker.com | sudo sh

# Don't start at boot for now (the drive is locked then). Chapter 6 can change this.
sudo systemctl disable --now docker.service docker.socket

# Store Docker's data on the encrypted drive, and use Tailscale's DNS
# (so containers can resolve your .ts.net name)
sudo mkdir -p /etc/docker /mnt/storage/docker
echo '{ "data-root": "/mnt/storage/docker", "dns": ["100.100.100.100", "1.1.1.1"] }' | sudo tee /etc/docker/daemon.json

# Safety net: Docker refuses to start unless the drive is mounted
sudo mkdir -p /etc/systemd/system/docker.service.d
printf '[Unit]\nConditionPathIsMountPoint=/mnt/storage\n' | sudo tee /etc/systemd/system/docker.service.d/wait-for-storage.conf
sudo systemctl daemon-reload

sudo systemctl start docker
sudo docker info | grep "Docker Root Dir"
```

- `100.100.100.100` is Tailscale's built-in DNS server. Without it, containers can't look up your `.ts.net` name.
- The `wait-for-storage.conf` override stops Docker from starting against an empty `/mnt/storage` folder on the microSD card, which would make your data look like it's gone.

**Check:** the last command prints `Docker Root Dir: /mnt/storage/docker`. Warnings about "No memory limit support" are normal on a Pi.

> This guide uses `sudo docker …` everywhere. Some guides add your user to the `docker` group so you can skip `sudo`. Don't: membership in that group is effectively full root access.

## Step 2: Make `unlock-storage` start Docker

Replace the script from chapter 3. Remember, the `EOF` goes on its own line:

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
sudo systemctl start docker
echo "Storage is unlocked and mounted at /mnt/storage, and Docker is running"
EOF
```

**Check:** `unlock-storage` prints the new message. The file keeps its executable permission from chapter 3.

## Step 3: Start the Nextcloud AIO master container

```bash
sudo mkdir -p /mnt/storage/ncdata

sudo docker run -d \
--init \
--sig-proxy=false \
--name nextcloud-aio-mastercontainer \
--restart always \
--publish 8080:8080 \
--env APACHE_PORT=11000 \
--env APACHE_IP_BINDING=127.0.0.1 \
--env SKIP_DOMAIN_VALIDATION=true \
--env NEXTCLOUD_DATADIR="/mnt/storage/ncdata" \
--volume nextcloud_aio_mastercontainer:/mnt/docker-aio-config \
--volume /var/run/docker.sock:/var/run/docker.sock:ro \
ghcr.io/nextcloud-releases/all-in-one:latest
```

- `NEXTCLOUD_DATADIR`: your files are stored on the encrypted drive.
- `APACHE_PORT` / `APACHE_IP_BINDING`: Nextcloud listens only inside the Pi, on port 11000. Tailscale serves it to your devices.
- `SKIP_DOMAIN_VALIDATION`: AIO's domain check can't reach a private tailnet address, so it's skipped.

**Check:** `sudo docker ps` lists `nextcloud-aio-mastercontainer` as `Up`.

## Step 4: Point Tailscale at Nextcloud

```bash
sudo tailscale serve --bg http://127.0.0.1:11000
tailscale serve status
```

**Check:** the status shows `https://<hostname>.<tailnet>` (tailnet only) proxying to `http://127.0.0.1:11000`. This setting survives restarts.

> If you renamed your tailnet and the old name still appears, run `sudo tailscale serve reset` and repeat the `serve` command. ⚠️ `serve reset` removes **every** Serve entry, so if you add more later (for example in the Notesnook bonus), you'll have to recreate those too.

## Step 5: Run the AIO setup wizard

1. Browse to `https://<pi-tailscale-ip>:8080` and accept the certificate warning. This admin page uses a self-signed certificate.
2. **Save the AIO passphrase** shown, then log in with it.
3. Enter your domain **exactly** as `<hostname>.<tailnet>`, with no `https://`.
   > ⚠️ The AIO interface can't change this domain later. (The [custom domain bonus](../part-2-bonus/01-custom-domain.md) shows the manual way, but it has side effects.)
4. Choose optional containers. Suggestions for a Pi:
   - **Office:** Collabora (documents never leave your server; best with ODF files) or Euro-Office (faster; best with Microsoft formats). Skip deprecated options.
   - ✅ **Talk** (chat and calls). You don't need to open port 3478 for use within your tailnet.
   - ✅ **Imaginary** (photo previews). Its warning about "server-side encryption" refers to Nextcloud's own encryption feature, not LUKS.
   - ✅ **Whiteboard** (optional, lightweight)
   - ❌ **ClamAV** and ❌ **Fulltextsearch**: too heavy for a Pi
5. Click **Save changes**, then **Download and start containers**. Allow 10 to 20 minutes.
6. When everything is green, **save the initial admin username and password** shown.
7. Open `https://<hostname>.<tailnet>` and log in.

**Check:** the Nextcloud dashboard loads with a padlock in the address bar and no certificate warning.

## Step 6: Secure your accounts

1. In **Personal settings → Security**, enable **TOTP two-factor authentication** and a **passkey**, and **generate backup codes**. Save the codes in your password manager.
2. Keep this emergency 2FA reset command somewhere safe. It runs on the Pi over SSH:

   ```bash
   sudo docker exec --user www-data nextcloud-aio-nextcloud php occ twofactorauth:disable <nextcloud-user> totp
   ```

3. Create a **separate personal account** for daily use (**Accounts → New account**). Keep `admin` for administration only, and log in to it only in the browser.

**Check:** log out and log back in. You're asked for a 2FA code.

## Step 7: Connect the apps

Install the Nextcloud desktop and phone apps and sign in to `https://<hostname>.<tailnet>` with your personal account. Tailscale must be on for each device.

- One desktop client can hold several accounts (account menu → **Add account**).

## Troubleshooting

| Problem | Fix |
|---|---|
| "Client Push" stuck on yellow, or the `notify_push` self-test fails | Containers can't resolve your `.ts.net` name. Confirm the `dns` entry in `/etc/docker/daemon.json`, run `sudo systemctl restart docker`, then on the AIO page click **Stop containers** → **Start containers**. |
| "Could not pull image… Retrying" | A temporary download problem, usually resolved by the automatic retry. |
| Dashboard "Recommended files" spinner never stops | Normal on a new, empty account. |
| You lost the AIO passphrase | `sudo docker exec nextcloud-aio-mastercontainer grep -o '"password": *"[^"]*"' /mnt/docker-aio-config/data/configuration.json` |
| AIO page says direct login is blocked because Nextcloud is running | Use the **Open Nextcloud AIO interface** button under **Administration settings → Overview**, or run `sudo docker stop nextcloud-aio-apache` and log in with the passphrase. |
| A removed or logged-out account keeps showing a login pop-up in the desktop client (Windows) | Quit the client fully, rename `%APPDATA%\Nextcloud\nextcloud.cfg` to `nextcloud.cfg.old`, and set the client up again. |
| `Cannot connect to the Docker daemon` after a restart | Docker is off because the drive is still locked. Run `unlock-storage`. |
