# MikroTik hEX monitoring with Telegram alerts

Telegram alerts for a MikroTik hEX:

| Port | What is monitored | When you get the alert |
|------|-------------------|------------------------|
| ether1 (ISP) | Internet reachability through the ISP link (ping via ether1) | When the connection **comes back**, with the outage duration |
| ether2 - ether5 | Link up / down on each LAN port | Within about 5 seconds if the internet works, otherwise as soon as it returns (with the original event time) |

## Why the ISP alert comes after the outage

When the ISP is down the router cannot reach Telegram, so a "down" alert cannot leave the router.
The script records when the outage started and sends the alert once the link is back.
If you want an instant alert, you need a second path out (for example an LTE backup WAN).

## Files

| File | Purpose |
|------|---------|
| `config.example.rsc` | Template for the `tg-notify` helper script (bot token and chat ID) |
| `isp-monitor.rsc` | ether1 / ISP monitor (Netwatch + probe route) |
| `port-watch.rsc` | ether2-5 watcher with queued alerts |
| `.gitignore` | Keeps your real `config.rsc` out of git |

Requirements: RouterOS v7, hEX (or any RouterOS device with `ether1`-`ether5`).

## Setup

### 1. Create the Telegram bot

1. In Telegram, open **@BotFather** and send `/newbot`. Follow the prompts and copy the **bot token**.
2. Open a chat with your new bot and send it any message (a bot cannot message you first).
3. Get your chat ID by opening `https://api.telegram.org/bot<BOT_TOKEN>/getUpdates` in a browser and reading `message.chat.id`.
   For a group chat, add the bot to the group, send a message there, and use the (negative) group ID.

### 2. Make sure the router clock is correct

Alerts include timestamps, so set NTP and a time zone first:

```routeros
/system ntp client set enabled=yes
/system clock set time-zone-name=Asia/Manila
```

(On older v7 builds the NTP server is set with `/system ntp client set servers=...`.)

### 3. Install the Telegram helper

1. Copy `config.example.rsc` to `config.rsc`.
2. Replace `<BOT_TOKEN>` and `<CHAT_ID>` with your real values.
3. Upload `config.rsc` to the router (WinBox: **Files**, drag and drop) and run:

```routeros
/import file-name=config.rsc
```

Test it:

```routeros
:global tgMsg "Hello%20from%20MikroTik"
/system script run tg-notify
```

You should get the message in Telegram within a few seconds. If not, see **Troubleshooting**.

### 4. Install the ISP monitor

1. Find your ISP gateway: `/ip route print where dst-address=0.0.0.0/0` (or `/ip dhcp-client print` if ether1 uses DHCP).
2. Edit `isp-monitor.rsc` and replace `<ISP-GATEWAY>` with that IP.
3. Upload and import:

```routeros
/import file-name=isp-monitor.rsc
```

If the ISP gives your router a changing gateway (DHCP), update the probe route when it changes, for example from the DHCP client script.

### 5. Install the port watcher

1. Open `port-watch.rsc` and edit the `ports` array labels to match what is plugged in, e.g. `"ether3"="AP%20living%20room"`.
2. Upload and import:

```routeros
/import file-name=port-watch.rsc
```

To re-install after editing, just import the file again. Each file removes its previous version first.

## Testing

**ISP alert (safe test, does not unplug your internet):** simulate an outage by disabling the probe route, wait about 30 seconds, then enable it again.

```routeros
/ip route disable [find comment="netwatch-probe-1"]
# wait ~30s, check /log print where message~"ISP down"
/ip route enable [find comment="netwatch-probe-1"]
# a Telegram message with the outage duration should arrive within ~20s
```

**LAN port alert:** unplug the cable on ether2-5. You should see `... DOWN at <time>` in Telegram within about 5 seconds, and `UP` when you plug it back in.

**Queued alert test:** disable the probe route, unplug a LAN cable, re-enable the route. The queued alert should arrive right after the ISP probe turns up.

## Tuning and notes

- **False alarms from Starlink micro-dropouts:** increase the Netwatch `interval` / `timeout`, or add a second probe (for example 8.8.8.8 with its own pinned route) and only alert when both fail.
- **PCs and phones:** a PC that sleeps or shuts down drops its link and triggers an alert. Only monitor ports with always-on devices, or remove noisy ports from the `ports` array.
- **Link up does not mean the device works:** a hung AP or camera keeps its link up. For always-on devices, add a Netwatch ping to the device IP (`/tool netwatch add host=192.168.x.x ...`).
- **Reboots:** global variables reset on reboot. The port watcher re-learns each port's state silently, and the ISP monitor sends an "outage start unknown" message the first time the probe comes up.
- **Alerts during a long outage** are kept in a queue limited to about 1500 characters; the oldest text is dropped first.

## Security

- The bot token is stored in the `tg-notify` script on the router. `/export` and backups include script sources, so do not share them. If the token leaks, revoke it in @BotFather with `/revoke`.
- Keep real credentials only in `config.rsc`, which is git-ignored. This repo should only contain placeholders.
- By default `/tool fetch` does not verify certificates. To enable verification, import the root CA that issued the `api.telegram.org` certificate on the router, then add `check-certificate=yes` to the `fetch` line in `tg-notify`.

## Troubleshooting

- **Nothing arrives:** run `/log print where message~"tg-notify"` and check the fetch error. Common causes are a wrong token or chat ID, you never sent a message to the bot, or no DNS / internet from the router.
- **Certificate errors with `check-certificate=yes`:** import the correct root CA, or temporarily remove that option while testing.
- **`running` always true or false on a port:** run `/interface ethernet print` and make sure the port name matches what is in the `ports` array.
- **Script errors:** `/system script run port-watch` in a terminal shows errors directly.
