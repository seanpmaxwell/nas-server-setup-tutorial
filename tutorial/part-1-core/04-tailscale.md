# 4. Tailscale (secure remote access)

Tailscale creates a private, encrypted network (a "tailnet") between your own devices. You can reach the Pi from anywhere without opening any ports on your router. Only devices signed in to your Tailscale account can connect.

## Step 1: Install Tailscale

1. Create a free account at **tailscale.com**, and install the Tailscale app on your computer and phone. Sign in to the same account on each.
2. On the Pi:

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up          # open the printed link and approve the Pi
tailscale ip -4            # the Pi's Tailscale address
```

The last command prints an address starting with `100.`. That's `<pi-tailscale-ip>`.

3. In the admin console at **login.tailscale.com/admin/machines**, open the Pi's **…** menu and choose **Disable key expiry**.

**Why:** otherwise the Pi is signed out of your tailnet after about six months, and remote access silently stops.

**Check:** the Pi appears on the Machines page as **Connected**, with "Expiry disabled".

## Step 2: Test the connection

With Tailscale running on your computer:

```bash
ssh <username>@<pi-tailscale-ip>
```

To confirm the connection really goes through Tailscale, run this on the Pi:

```bash
echo $SSH_CONNECTION
```

**Check:** the first address shown starts with `100.`, which is your computer's Tailscale address.

> The "Last login" line at login shows your **previous** session, not the current one.

## Step 3: Enable HTTPS and choose your tailnet name

In **login.tailscale.com/admin/dns**:

- Make sure **MagicDNS** is on.
- Click **Enable HTTPS** (under HTTPS Certificates).
- Optional: **Rename tailnet** to a random two-word name. You can re-roll the suggestions, but you can't type your own words.

> ⚠️ **Settle on the tailnet name now.** Nextcloud's address (next chapter) is based on it. The AIO interface can't change that address later, and passkeys are tied to it.

Find the Pi's full name on its machine page. It's `<hostname>.<tailnet>`, for example `homeserver.tail1234ab.ts.net`.

**Check:** on your computer, `ping <hostname>.<tailnet>` gets replies from `<pi-tailscale-ip>`.

## Troubleshooting

| Problem | Fix |
|---|---|
| Windows: `tailscale status` shows "NoState" | Open Tailscale from the Start menu and log in, or restart the computer. |
| `<hostname>` resolves to the LAN IP instead | Your router knows the name too. Use `<pi-tailscale-ip>` when you want to be sure you're testing Tailscale. |
| A device can't see the Pi | Check it's signed in to the **same account and login provider**. Signing in with Google instead of GitHub, even with the same email, puts you in a different tailnet. |
