# Self-Hosting Your Own Storage Server Using a Raspberry Pi

**A step-by-step guide to an encrypted home file server with Nextcloud and Tailscale.**

An encrypted, self-hosted alternative to Dropbox or Google Drive that you can reach securely from anywhere through Tailscale, with no open ports on your router.

👉 **[Start the tutorial](tutorial/README.md)**

- **Part 1 (core):** hardware and OS, SSH, LUKS-encrypted storage, Tailscale, Docker and Nextcloud All-in-One, maintenance and security
- **Part 2 (bonus):** a custom domain through a cloud proxy, Time Machine backups over SMB, self-hosted Notesnook, and Notesnook on your custom domain

Licensed under the terms in [LICENSE](LICENSE), except [`docker-compose.yml`](tutorial/part-2-bonus/notesnook-files/docker-compose.yml), which is adapted from the Notesnook sync server and stays under AGPL-3.0.
