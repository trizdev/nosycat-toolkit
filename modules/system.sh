#!/usr/bin/env bash
# modules/system.sh - hostname, time, locale, memory, disk, limits, load.
# shellcheck shell=bash

_meminfo() { awk -v k="$1" '$1==k":"{print $2; exit}' /proc/meminfo 2>/dev/null; }

mod_system() {
  local v tz

  # SYS-001 hostname resolves locally (sudo prints "unable to resolve host" otherwise)
  if t 5 getent hosts "$HOST_NAME" >/dev/null 2>&1; then
    ok SYS-001 "hostname $HOST_NAME resolves" ""
  else
    warn SYS-001 "hostname $HOST_NAME does not resolve" "sudo prints 'unable to resolve host', some daemons (postfix, java apps) fail to start" "echo \"127.0.1.1 $HOST_NAME\" | sudo tee -a /etc/hosts"
  fi

  # SYS-002 timezone
  tz=""
  if have timedatectl; then tz="$(q timedatectl show -p Timezone --value)"; fi
  if [ -z "$tz" ] && [ -r /etc/timezone ]; then tz="$(head -n1 /etc/timezone)"; fi
  if [ -z "$tz" ] && [ -L /etc/localtime ]; then tz="$(readlink /etc/localtime)"; tz="${tz#*zoneinfo/}"; fi
  if [ -z "$tz" ]; then
    warn SYS-002 "timezone not set" "log timestamps and cron schedules become ambiguous" "sudo timedatectl set-timezone UTC"
  else
    ok SYS-002 "timezone: $tz" "UTC is the usual choice for servers; local time is fine if deliberate"
  fi

  # SYS-003 NTP
  v=""
  if have timedatectl && systemd_up; then v="$(q timedatectl show -p NTPSynchronized --value)"; fi
  if [ "$v" = "yes" ]; then
    ok SYS-003 "clock synchronized (NTP)" ""
  elif [ "$v" = "no" ]; then
    warn SYS-003 "clock not synchronized" "clock drift breaks TLS, TOTP, log correlation and distributed databases" "sudo timedatectl set-ntp true   # or install chrony"
  elif have chronyc; then
    if q chronyc tracking | grep -q 'Leap status *: Normal'; then ok SYS-003 "clock synchronized (chrony)" ""
    else warn SYS-003 "chrony not synchronized" "clock drift breaks TLS, TOTP and log correlation" "chronyc sources -v"; fi
  elif [ "$VIRT_KIND" = "container" ]; then
    skip SYS-003 "clock synchronization" "container uses the host clock"
  else
    warn SYS-003 "clock sync status unknown" "no timedatectl/chronyc found" "install chrony (or systemd-timesyncd)"
  fi

  # SYS-004 locale
  local lerr lang=""
  lerr="$(LC_ALL='' locale 2>&1 >/dev/null)"
  for v in /etc/default/locale /etc/locale.conf; do
    [ -r "$v" ] && lang="$(awk -F= '/^LANG=/{gsub(/"/,"",$2);print $2; exit}' "$v")" && [ -n "$lang" ] && break
  done
  lang="${lang:-${LANG:-}}"
  if [ -n "$lerr" ]; then
    warn SYS-004 "locale errors reported" "$(printf '%s' "$lerr" | head -n1); perl, apt and python print warnings or mis-handle UTF-8" "sudo localectl set-locale LANG=C.UTF-8   # or dpkg-reconfigure locales"
  elif [ -z "$lang" ] || [ "$lang" = "C" ] || [ "$lang" = "POSIX" ]; then
    warn SYS-004 "no UTF-8 system locale (LANG=${lang:-unset})" "non-ASCII filenames and app output may break" "sudo localectl set-locale LANG=C.UTF-8"
  else
    ok SYS-004 "locale: $lang" ""
  fi

  # SYS-005 swap / SYS-006 swappiness
  local mem_kb swap_kb avail_kb sw
  mem_kb="$(_meminfo MemTotal)"; swap_kb="$(_meminfo SwapTotal)"; avail_kb="$(_meminfo MemAvailable)"
  sw="$(cat /proc/sys/vm/swappiness 2>/dev/null)"
  if [ -z "$mem_kb" ]; then
    skip SYS-005 "swap" "/proc/meminfo unreadable"
  elif [ "${swap_kb:-0}" -eq 0 ]; then
    if [ "$mem_kb" -lt 8388608 ]; then
      warn SYS-005 "no swap configured ($((mem_kb / 1024)) MiB RAM)" "on small VPS a memory spike (apt, composer, builds) triggers the OOM killer instead of slowing down" "sudo fallocate -l 2G /swapfile && sudo chmod 600 /swapfile && sudo mkswap /swapfile && sudo swapon /swapfile   # then add to /etc/fstab"
    else
      ok SYS-005 "no swap ($((mem_kb / 1024)) MiB RAM)" "acceptable with this much RAM"
    fi
  else
    ok SYS-005 "swap: $((swap_kb / 1024)) MiB" ""
  fi
  if [ -n "$sw" ] && [ "${swap_kb:-0}" -gt 0 ] && [ "$sw" -gt 60 ]; then
    warn SYS-006 "vm.swappiness=$sw" "high swappiness pushes app memory to disk early; servers usually use 10-30" "echo 'vm.swappiness=10' | sudo tee /etc/sysctl.d/99-swappiness.conf && sudo sysctl --system"
  elif [ -n "$sw" ]; then
    ok SYS-006 "vm.swappiness=$sw" ""
  else
    skip SYS-006 "vm.swappiness" "not readable"
  fi

  # SYS-007 disk / SYS-008 inodes
  local dfx=(-x tmpfs -x devtmpfs -x overlay -x squashfs -x efivarfs -x nsfs)
  # Keep an unreadable result distinct from a real 0% reading.
  local line pct mnt worst_d=-1 worst_i=-1 msg_d=() msg_i=()
  while read -r line; do
    pct="$(printf '%s' "$line" | awk '{print $(NF-1)}' | tr -d '%')"; mnt="${line##* }"
    case "$pct" in ''|*[!0-9]*) continue ;; esac
    if [ "$pct" -ge 80 ]; then msg_d+=("$mnt ${pct}%"); fi
    [ "$pct" -gt "$worst_d" ] && worst_d="$pct"
  done < <(q df -P "${dfx[@]}" | tail -n +2)
  while read -r line; do
    pct="$(printf '%s' "$line" | awk '{print $(NF-1)}' | tr -d '%')"; mnt="${line##* }"
    case "$pct" in ''|*[!0-9]*) continue ;; esac
    if [ "$pct" -ge 80 ]; then msg_i+=("$mnt ${pct}%"); fi
    [ "$pct" -gt "$worst_i" ] && worst_i="$pct"
  done < <(q df -Pi "${dfx[@]}" | tail -n +2)
  if [ "$worst_d" -lt 0 ]; then skip SYS-007 "disk usage" "not readable"
  elif [ "$worst_d" -ge 90 ]; then fail SYS-007 "disk almost full: $(join ', ' "${msg_d[@]}")" "full disks corrupt databases, stop logging and break package installs" "sudo du -xh / --max-depth=2 | sort -h | tail -20"
  elif [ "$worst_d" -ge 80 ]; then warn SYS-007 "disk usage high: $(join ', ' "${msg_d[@]}")" "little headroom for logs, images and updates" "sudo du -xh / --max-depth=2 | sort -h | tail -20"
  else ok SYS-007 "disk usage below 80% (max ${worst_d}%)" ""; fi
  if [ "$worst_i" -lt 0 ]; then skip SYS-008 "inode usage" "not readable"
  elif [ "$worst_i" -ge 90 ]; then fail SYS-008 "inodes almost exhausted: $(join ', ' "${msg_i[@]}")" "'No space left on device' even with free bytes; usually session/cache files" "sudo find / -xdev -type d -size +1M   # dirs with many entries"
  elif [ "$worst_i" -ge 80 ]; then warn SYS-008 "inode usage high: $(join ', ' "${msg_i[@]}")" "many small files (cache, sessions, mail queue)" "sudo find / -xdev -type d -size +1M"
  else ok SYS-008 "inode usage below 80% (max ${worst_i}%)" ""; fi

  # SYS-009 open files limit
  local soft hard
  soft="$(ulimit -Sn 2>/dev/null)"; hard="$(ulimit -Hn 2>/dev/null)"
  if [ "$hard" != "unlimited" ] && [ -n "$hard" ] && [ "$hard" -lt 65536 ]; then
    warn SYS-009 "open files hard limit is $hard (soft $soft)" "databases, proxies and node apps hit 'Too many open files' under load" "set 'LimitNOFILE=65536' in the service unit, or raise nofile in /etc/security/limits.conf"
  else
    ok SYS-009 "open files limit: soft $soft, hard $hard" "services can raise their own soft limit (LimitNOFILE=)"
  fi

  # SYS-010 OOM kills in the last 7 days
  local oom="" kernel_log="" kernel_probe log_rc=0
  if have journalctl && systemd_up; then
    # An empty time window is valid only after proving the log is readable.
    if kernel_probe="$(q journalctl -k -b -n 1 -q)" && [ -n "$kernel_probe" ]; then
      oom=0
      kernel_log="$(q journalctl -k --since '-7d' --no-pager -q)" || log_rc=$?
    fi
  elif [ "$IS_ROOT" -eq 1 ] && have dmesg; then
    kernel_log="$(q dmesg)" || log_rc=$?
  fi
  if [ -n "$kernel_log" ]; then
    oom="$(printf '%s\n' "$kernel_log" | grep -ciE 'out of memory|oom-kill|killed process')"
  fi
  # Partial reads still prove OOM events, but cannot prove their absence.
  if [ "$log_rc" -ne 0 ] && [ "${oom:-0}" -eq 0 ]; then oom=""; fi
  if [ -z "$oom" ]; then
    skip SYS-010 "recent OOM kills" "kernel log not readable (needs root/journal)"
  elif [ "$oom" -gt 0 ]; then
    warn SYS-010 "$oom OOM-killer event(s) in the kernel log (7d)" "processes were killed for lack of memory; services may be restarting silently" "journalctl -k --since -7d | grep -i 'killed process'"
  else
    ok SYS-010 "no OOM kills in the last 7 days" ""
  fi

  # SYS-011 memory pressure
  if [ -n "$mem_kb" ] && [ -n "$avail_kb" ]; then
    local pa=$((avail_kb * 100 / mem_kb))
    if [ "$pa" -lt 10 ]; then fail SYS-011 "only ${pa}% RAM available ($((avail_kb / 1024)) of $((mem_kb / 1024)) MiB)" "the box is about to swap heavily or OOM" "ps aux --sort=-rss | head"
    elif [ "$pa" -lt 20 ]; then warn SYS-011 "${pa}% RAM available ($((avail_kb / 1024)) of $((mem_kb / 1024)) MiB)" "little headroom for spikes" "ps aux --sort=-rss | head"
    else ok SYS-011 "RAM: $((avail_kb / 1024)) of $((mem_kb / 1024)) MiB available (${pa}%)" ""; fi
  else
    skip SYS-011 "memory" "/proc/meminfo unreadable"
  fi

  # SYS-012 load vs CPUs (5-minute average)
  local cpus l5
  cpus="$(nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo)"
  l5="$(awk '{print $2}' /proc/loadavg 2>/dev/null)"
  if [ -n "$l5" ] && [ -n "$cpus" ]; then
    local ratio
    ratio="$(awk -v l="$l5" -v c="$cpus" 'BEGIN{printf "%d", (l/c)*100}')"
    if [ "$ratio" -ge 200 ]; then fail SYS-012 "load $l5 on $cpus vCPU (${ratio}%)" "sustained overload; requests queue and time out" "top -o %CPU"
    elif [ "$ratio" -ge 100 ]; then warn SYS-012 "load $l5 on $cpus vCPU (${ratio}%)" "CPU saturated or processes blocked on I/O (steal time on oversold VPS?)" "top   # check %st (steal) and %wa (iowait)"
    else ok SYS-012 "load $l5 on $cpus vCPU" ""; fi
  else
    skip SYS-012 "load average" "/proc/loadavg unreadable"
  fi
}
