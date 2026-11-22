# 1. Hardware and OS

In this chapter you assemble the Pi and put Raspberry Pi OS on the microSD card. See the [shopping list](../README.md#shopping-list) for the parts.

> Kits often include extras you don't need, such as a passive heatsink set or a camera ribbon cable. Use only **one** cooler. The active one (with a fan) is better for a server that runs 24/7.

## Step 1: Assemble the Pi

1. **Discharge static** by touching something metal. Handle the Pi by its edges.
2. **Attach the active cooler.** Peel the film off the thermal pads (or place the pads on the chips), line up the spring pins with the board's holes, and press evenly until they click. Check the alignment first, because the pins are hard to remove.
3. **Plug the fan cable into the 4-pin `FAN` connector.** It's tiny and keyed, so it fits only one way. Press on the plug body, not the wires. When it's fully seated, no metal pins show.
4. **Tuck the fan wire** so it isn't over the fan intake or pinched by the lid.
5. **Mount the Pi in the case**, following the case's instructions.

**Check:** the cooler doesn't wobble, and the fan cable is fully seated. You'll test the fan in chapter 2.

## Step 2: Flash the operating system

1. On your computer, install **Raspberry Pi Imager** from raspberrypi.com/software.
2. Insert the microSD card using the USB card reader. The microSD slot is often labeled **TF**. If your computer offers to format the card, click **Cancel**.
3. In Imager, choose:
   - **Device:** Raspberry Pi 5
   - **OS:** Raspberry Pi OS (64-bit). The desktop version makes first setup easier. You can switch the Pi to console-only later (chapter 7).
   - **Storage:** your microSD card. Check the size so you don't pick the wrong disk.
4. In **Customisation**:
   - **Hostname:** your choice. This becomes `<hostname>`.
   - **Username and password:** don't use `pi` or `admin`. The username becomes `<username>`. Save the password in your password manager.
   - **Wi-Fi:** optional. Ethernet is recommended for the server.
   - **Remote access:** enable **SSH** with **password authentication**. You'll switch to keys in chapter 7.
   - **Raspberry Pi Connect:** leave it off. Tailscale is used instead.
5. Check the summary, click **Write**, and wait until it finishes **verifying**.

> Double-check which box you typed the hostname into and which one the username. They're easy to mix up. Later, the Terminal prompt shows `username@hostname`, so you'll know.

**Check:** Imager reports that the write was successful and the card was verified.

## Troubleshooting

| Problem | Fix |
|---|---|
| The fan connector won't go in | It's keyed. Turn it around rather than pushing harder. |
| Your computer asks to format the card after writing | Click **Cancel**. Your computer can't read the Pi's Linux partition, and that's normal. |
| Imager can't see the card | Try another USB port or card reader, and make sure the card is pushed fully into the reader. |
