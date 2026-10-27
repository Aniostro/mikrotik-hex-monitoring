# isp-monitor.rsc
# Watches internet reachability through ether1 (the ISP port) and sends a Telegram
# message when the connection COMES BACK, including how long it was down.
# (Telegram cannot be reached while the ISP is down, so the alert cannot leave the router earlier.)
#
# BEFORE IMPORTING: replace <ISP-GATEWAY> with the gateway IP of your ISP / Starlink link on ether1.
# Requires RouterOS v7 (uses [:timestamp]) and the tg-notify script from config.rsc.

# --- clean up older versions so the file can be re-imported safely ---
/tool netwatch remove [find comment="isp-monitor"]
/system script remove [find name=isp-down]
/system script remove [find name=isp-up]
/ip route remove [find comment="netwatch-probe-1"]

# --- pin the probe IP to ether1 so the check cannot leak out another WAN ---
/ip route add dst-address=1.1.1.1/32 gateway=<ISP-GATEWAY> comment="netwatch-probe-1"

# --- runs when the probe goes down: remember when the outage started ---
/system script add name=isp-down policy=read,write,test source={
  :global wanDownTs
  :if ([:typeof $wanDownTs] != "time") do={ :set wanDownTs [:timestamp] }
  :log warning "ISP down (ether1 probe failed)"
}

# --- runs when the probe comes back: send the alert, retry a few times ---
/system script add name=isp-up policy=read,write,test source={
  :global wanDownTs
  :global tgMsg
  :global tgOk
  :if ([:typeof $wanDownTs] = "time") do={
    :local dur ([:timestamp] - $wanDownTs)
    :set tgMsg ("ISP%20is%20back%20online.%20Outage%20lasted%20" . $dur)
  } else={
    :set tgMsg "ISP%20is%20online%20(outage%20start%20unknown%2C%20router%20may%20have%20rebooted)"
  }
  :local tries 0
  :set tgOk false
  :while (!$tgOk && $tries < 5) do={
    :set tries ($tries + 1)
    /system script run tg-notify
    :if (!$tgOk) do={ :delay 5s }
  }
  :if ($tgOk) do={ :set wanDownTs "" }
  :log info "ISP up, telegram sent: $tgOk"
}

# --- the monitor itself ---
/tool netwatch add host=1.1.1.1 interval=15s timeout=3s comment="isp-monitor" \
  down-script="/system script run isp-down" \
  up-script="/system script run isp-up"
