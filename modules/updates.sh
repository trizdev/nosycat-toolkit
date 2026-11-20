#!/usr/bin/env bash
# modules/updates.sh - pending updates, automatic security updates, reboot needed.
# Uses only local package metadata where possible; never refreshes or installs.
# shellcheck shell=bash

mod_updates() {
  local total="" sec="" note="" age out rc

  case "$PKG_MGR" in
    apt-get)
      local sim
      if sim="$(t 60 apt-get -s -o Debug::NoLocking=1 dist-upgrade 2>/dev/null)"; then
        total="$(printf '%s\n' "$sim" | grep -c '^Inst ')"
        sec="$(printf '%s\n' "$sim" | grep '^Inst ' | grep -ci 'security')"
      fi
      if [ -d /var/lib/apt/lists ]; then
        age="$(find /var/lib/apt/lists -maxdepth 1 -name '*_Packages*' -mtime -7 2>/dev/null | head -n1)"
        [ -z "$age" ] && note=" (package lists older than 7 days or never fetched; run 'sudo apt update' for accurate counts)"
      fi ;;
    dnf|yum)
      out="$(t 90 "$PKG_MGR" -q check-update 2>/dev/null)"; rc=$?
      if [ "$rc" -eq 100 ]; then total="$(printf '%s\n' "$out" | awk 'NF==3 && $1 ~ /\./' | wc -l)"
      elif [ "$rc" -eq 0 ]; then total=0; fi
      sec="$(t 90 "$PKG_MGR" -q updateinfo list --security 2>/dev/null | awk 'NF>=3' | wc -l)" ;;
    apk)
      if out="$(q apk version -l '<')"; then
        total="$(printf '%s\n' "$out" | tail -n +2 | grep -c .)"
      fi
      note=" (uses cached index; run 'apk update' for accurate counts)" ;;
    pacman)
      if have checkupdates; then
        out="$(t 60 checkupdates 2>/dev/null)"; rc=$?
        if [ "$rc" -eq 0 ]; then total="$(printf '%s\n' "$out" | grep -c .)"
        elif [ "$rc" -eq 2 ]; then total=0; fi
      else
        # pacman -Qu also returns 1 when no upgrades are available.
        out="$(q pacman -Qu)"; rc=$?
        if [ "$rc" -eq 0 ]; then total="$(printf '%s\n' "$out" | grep -c .)"
        elif [ "$rc" -eq 1 ] && [ -z "$out" ]; then total=0; fi
        note=" (local sync db; install pacman-contrib for checkupdates)"
      fi ;;
    zypper)
      out="$(t 60 zypper -q lu 2>/dev/null)"; rc=$?
      if [ "$rc" -eq 0 ]; then
        total="$(printf '%s\n' "$out" | grep -c '^v ')"
      elif [ "$rc" -eq 106 ] && printf '%s\n' "$out" | grep '^v ' >/dev/null; then
        total="$(printf '%s\n' "$out" | grep -c '^v ')"
        note=" (partial: a repository was skipped)"
      fi
      sec="$(t 60 zypper -q lp --category security 2>/dev/null | grep -c '^[a-zA-Z].*|.*security')" ;;
  esac

  if [ -z "$total" ]; then
    skip UPD-001 "pending updates" "no supported package manager or query timed out"
  elif [ -n "$sec" ] && [ "$sec" -gt 0 ]; then
    fail UPD-001 "$total pending update(s), $sec security$note" "fresh images are often weeks behind; patch before exposing services" "$(_upd_cmd)"
  elif [ "$total" -gt 0 ]; then
    warn UPD-001 "$total pending update(s)$note" "outdated packages accumulate known vulnerabilities and bigger upgrade jumps later" "$(_upd_cmd)"
  else
    ok UPD-001 "no pending updates$note" ""
  fi

  # UPD-002 automatic security updates
  case "$PKG_MGR" in
    apt-get)
      if dpkg-query -W -f='${Status}' unattended-upgrades 2>/dev/null | grep -q 'install ok installed'; then
        if grep -rqsE 'APT::Periodic::Unattended-Upgrade[[:space:]]+"1"' /etc/apt/apt.conf.d/; then
          ok UPD-002 "unattended-upgrades installed and enabled" ""
        else
          warn UPD-002 "unattended-upgrades installed but not enabled" "security patches will not be applied automatically" "sudo dpkg-reconfigure -plow unattended-upgrades"
        fi
      else
        warn UPD-002 "automatic security updates not configured" "an unattended server falls behind on security fixes" "sudo apt install unattended-upgrades && sudo dpkg-reconfigure -plow unattended-upgrades"
      fi ;;
    dnf|yum)
      local tm found=""
      for tm in dnf-automatic.timer dnf-automatic-install.timer dnf5-automatic.timer yum-cron; do
        if unit_enabled "$tm"; then found="$tm"; break; fi
      done
      if [ -n "$found" ]; then ok UPD-002 "automatic updates enabled ($found)" ""
      else warn UPD-002 "automatic security updates not configured" "an unattended server falls behind on security fixes" "sudo dnf install dnf-automatic && sudo sed -i 's/^upgrade_type.*/upgrade_type = security/;s/^apply_updates.*/apply_updates = yes/' /etc/dnf/automatic.conf && sudo systemctl enable --now dnf-automatic.timer"; fi ;;
    zypper)
      if unit_enabled packagekit-background.timer || ls /etc/cron.*/*zypper* >/dev/null 2>&1; then ok UPD-002 "automatic updates configured" ""
      else warn UPD-002 "automatic updates not configured" "" "consider a zypper patch timer"; fi ;;
    apk|pacman)
      skip UPD-002 "automatic updates" "$PKG_MGR has no standard unattended-upgrade mechanism; schedule reviewed updates instead" ;;
    *) skip UPD-002 "automatic updates" "unknown package manager" ;;
  esac

  # UPD-003 reboot required
  if [ "$VIRT_KIND" = "container" ]; then
    skip UPD-003 "reboot required" "inside a container (host kernel)"
  elif [ -f /var/run/reboot-required ]; then
    local pk=""
    [ -r /var/run/reboot-required.pkgs ] && pk=" ($(sort -u /var/run/reboot-required.pkgs | head -n 5 | tr '\n' ' '))"
    warn UPD-003 "reboot required$pk" "updates (often the kernel or libc) only take effect after a reboot" "sudo reboot   # during a maintenance window"
  elif have needs-restarting && ! q needs-restarting -r >/dev/null; then
    warn UPD-003 "reboot required (needs-restarting)" "core libraries or kernel were updated" "sudo reboot   # during a maintenance window"
  elif [ ! -d "/lib/modules/$(uname -r)" ] && [ ! -d "/usr/lib/modules/$(uname -r)" ]; then
    warn UPD-003 "running kernel $(uname -r) is no longer installed" "kernel was upgraded; loading new modules (e.g. for docker, wireguard) will fail until reboot" "sudo reboot"
  else
    ok UPD-003 "no reboot pending" ""
  fi
}

_upd_cmd() {
  case "$PKG_MGR" in
    apt-get) echo "sudo apt update && sudo apt full-upgrade" ;;
    dnf|yum) echo "sudo $PKG_MGR upgrade --refresh" ;;
    apk) echo "sudo apk update && sudo apk upgrade" ;;
    pacman) echo "sudo pacman -Syu" ;;
    zypper) echo "sudo zypper patch" ;;
  esac
}
