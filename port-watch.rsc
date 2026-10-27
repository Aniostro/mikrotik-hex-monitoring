# port-watch.rsc
# Watches ether2-ether5 (LAN ports) every 5 seconds.
# - Port state changes are queued with their event time.
# - The queue is sent to Telegram as soon as the ISP probe (isp-monitor) is up, so alerts are
#   near real time while the internet works and are delivered after an outage if it does not.
#
# Requires the tg-notify script (config.rsc) and the "isp-monitor" netwatch entry (isp-monitor.rsc).
# Edit the labels in the "ports" array to match what is plugged in. Use %20 for spaces.

# --- clean up older versions so the file can be re-imported safely ---
/system scheduler remove [find name=port-watch-run]
/system script remove [find name=port-watch]

/system script add name=port-watch policy=read,write,test source={
  :global portState
  :global alertQueue
  :global tgMsg
  :global tgOk
  :if ([:typeof $portState] != "array") do={ :set portState [:toarray ""] }
  :if ([:typeof $alertQueue] = "nothing") do={ :set alertQueue "" }

  # port name = label shown in the alert
  :local ports {"ether2"="ether2"; "ether3"="ether3"; "ether4"="ether4"; "ether5"="ether5"}
  :local now [/system clock get time]

  # 1. Detect changes and queue messages (first run only records the baseline)
  :foreach p,label in=$ports do={
    :local up [/interface ethernet get $p running]
    :local prev ($portState->$p)
    :if ([:typeof $prev] = "nothing") do={
      :set ($portState->$p) $up
    } else={
      :if ($prev != $up) do={
        :set ($portState->$p) $up
        :local s "DOWN"
        :if ($up) do={ :set s "UP" }
        :set alertQueue ($alertQueue . $label . "%20" . $s . "%20at%20" . $now . "%0A")
      }
    }
  }

  # keep the queue from growing forever during a very long outage (drops the oldest text)
  :if ([:len $alertQueue] > 1500) do={
    :set alertQueue [:pick $alertQueue ([:len $alertQueue] - 1500) [:len $alertQueue]]
  }

  # 2. Flush the queue only when the ISP probe is up
  :if ([:len $alertQueue] > 0) do={
    :local ispUp false
    :do { :set ispUp ([/tool netwatch get [find comment="isp-monitor"] status] = "up") } on-error={}
    :if ($ispUp) do={
      :set tgMsg $alertQueue
      /system script run tg-notify
      :if ($tgOk) do={ :set alertQueue "" }
    }
  }
}

/system scheduler add name=port-watch-run interval=5s policy=read,write,test \
  on-event="/system script run port-watch"
