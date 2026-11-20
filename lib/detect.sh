#!/usr/bin/env bash
# lib/detect.sh - environment facts shared by every module.
# shellcheck shell=bash
# shellcheck disable=SC2034  # globals are consumed by other sourced files

OS_ID="unknown" OS_LIKE="" OS_NAME="unknown" OS_FAMILY="unknown"
VIRT="unknown" VIRT_KIND="unknown" PROVIDER="unknown" PROVIDER_SRC=""
PKG_MGR="none" INIT_SYS="unknown"
FW_ACTIVE="none"   # ufw | firewalld | nftables | iptables | none | unknown
FW_BANNERS=""      # IP ban tools seen in the rules: fail2ban, crowdsec (not firewalls)
HOST_NAME="$(hostname 2>/dev/null || cat /proc/sys/kernel/hostname 2>/dev/null || echo unknown)"

_read1() { [ -r "$1" ] && head -n1 "$1" 2>/dev/null | tr -d '\0'; }

detect_os() {
  if [ -r /etc/os-release ]; then
    OS_ID="$(. /etc/os-release && printf '%s' "${ID:-unknown}")"
    OS_LIKE="$(. /etc/os-release && printf '%s' "${ID_LIKE:-}")"
    OS_NAME="$(. /etc/os-release && printf '%s' "${PRETTY_NAME:-${NAME:-unknown}}")"
  fi
  case " $OS_ID $OS_LIKE " in
    *" debian "*|*" ubuntu "*) OS_FAMILY="debian" ;;
    *" rhel "*|*" fedora "*|*" centos "*|*" rocky "*|*" almalinux "*) OS_FAMILY="rhel" ;;
    *" alpine "*) OS_FAMILY="alpine" ;;
    *" arch "*) OS_FAMILY="arch" ;;
    *" suse "*|*" opensuse "*) OS_FAMILY="suse" ;;
  esac
}

detect_pkg() {
  local m
  for m in apt-get dnf yum apk pacman zypper; do
    if have "$m"; then PKG_MGR="$m"; return; fi
  done
}

detect_init() {
  if [ -d /run/systemd/system ]; then INIT_SYS="systemd"
  elif have rc-status || [ -d /run/openrc ]; then INIT_SYS="openrc"
  else
    INIT_SYS="$(ps -o comm= -p 1 2>/dev/null || _read1 /proc/1/comm || echo unknown)"
  fi
}

detect_virt() {
  local v=""
  if have systemd-detect-virt; then
    if v="$(q systemd-detect-virt --container)" && [ -n "$v" ] && [ "$v" != "none" ]; then
      VIRT="$v"; VIRT_KIND="container"; return
    fi
    if v="$(q systemd-detect-virt --vm)" && [ -n "$v" ] && [ "$v" != "none" ]; then
      VIRT="$v"; VIRT_KIND="vm"; return
    fi
    if [ "$v" = "none" ]; then VIRT="none"; VIRT_KIND="baremetal"; fi
  fi
  # Fallbacks for systems without systemd.
  if [ -f /.dockerenv ]; then VIRT="docker"; VIRT_KIND="container"; return; fi
  if [ -f /run/.containerenv ]; then VIRT="podman"; VIRT_KIND="container"; return; fi
  if grep -qa 'container=lxc' /proc/1/environ 2>/dev/null || grep -q '/lxc/' /proc/1/cgroup 2>/dev/null; then
    VIRT="lxc"; VIRT_KIND="container"; return
  fi
  if grep -qE '/(docker|kubepods|containerd)' /proc/1/cgroup 2>/dev/null; then
    VIRT="docker"; VIRT_KIND="container"; return
  fi
  if [ "$VIRT_KIND" = "unknown" ] && grep -qw hypervisor /proc/cpuinfo 2>/dev/null; then
    VIRT="$(_read1 /sys/class/dmi/id/product_name)"; VIRT="${VIRT:-hypervisor}"; VIRT_KIND="vm"
  fi
}

detect_provider() {
  local blob="" f id=""
  if [ -r /run/cloud-init/cloud-id ]; then id="$(_read1 /run/cloud-init/cloud-id)"; fi
  if [ -z "$id" ] && have cloud-id; then id="$(q cloud-id)"; fi
  for f in sys_vendor product_name bios_vendor chassis_asset_tag board_vendor; do
    blob="$blob $(_read1 "/sys/class/dmi/id/$f")"
  done
  blob="$blob $HOST_NAME"
  case "$blob" in
    *Hetzner*) PROVIDER="hetzner" ;;
    *DigitalOcean*) PROVIDER="digitalocean" ;;
    *Amazon*|*EC2*|*ec2*) PROVIDER="aws" ;;
    *Google*) PROVIDER="gcp" ;;
    *7783-7084-3265-9085-8269-3286-77*|*Microsoft*) PROVIDER="azure" ;;
    *OracleCloud*) PROVIDER="oracle" ;;
    *Linode*|*Akamai*) PROVIDER="linode" ;;
    *Vultr*) PROVIDER="vultr" ;;
    *OVH*) PROVIDER="ovh" ;;
    *Scaleway*) PROVIDER="scaleway" ;;
    *UpCloud*) PROVIDER="upcloud" ;;
    *contabo*|*Contabo*|*vmi[0-9]*) PROVIDER="contabo" ;;
  esac
  if [ "$PROVIDER" != "unknown" ]; then PROVIDER_SRC="dmi/hostname"; fi
  if [ -n "$id" ] && [ "$id" != "none" ]; then
    if [ "$PROVIDER" = "unknown" ]; then PROVIDER="$id"; fi
    PROVIDER_SRC="${PROVIDER_SRC:+$PROVIDER_SRC, }cloud-init ($id)"
  fi
}

# nft_input_filters -> reads `nft list ruleset` on stdin; exits 0 when some chain
# hooked on input actually filters: policy drop, or a drop/reject rule in that
# chain or in a chain it jumps/goes to (same table). Drops elsewhere (e.g.
# Docker's DOCKER-ISOLATION-* chains, reached from FORWARD) do not count, and
# neither do:
#   - a lone "ct state invalid drop";
#   - ban lists: rules that only drop/reject listed source addresses
#     ("ip saddr @set", "ip6 saddr { ... }", "ip saddr 192.0.2.1"). An
#     allowlist ("saddr != @trusted drop") still counts;
#   - the tables fail2ban and CrowdSec create (f2b-*, crowdsec*), whatever
#     they contain.
# Optional $1 restricts table families (e.g. "inet|ip6" for IPv6).
nft_input_filters() {
  awk -v families="${1:-}" '
    function filters(c, depth,   i, n, parts) {
      if (depth > 8) return 0
      if (dropper[c]) return 1
      n = split(jumps[c], parts, " ")
      for (i = 1; i <= n; i++) if (parts[i] != "" && filters(parts[i], depth + 1)) return 1
      return 0
    }
    /^[[:space:]]*table[[:space:]]/ { tbl = $2 ":" $3; banner = ($3 ~ /^(f2b-|crowdsec)/); ch = ""; next }
    families != "" && tbl !~ ("^(" families "):") { next }
    banner { next }
    /^[[:space:]]*chain[[:space:]]/ { ch = tbl "/" $2; next }
    ch == "" { next }
    /^[[:space:]]*}/ { ch = ""; next }
    /type filter hook input/ {
      input[ch] = 1
      if ($0 ~ /policy drop/) dropper[ch] = 1
      next
    }
    /(^|[[:space:]])(jump|goto)[[:space:]]/ {
      for (i = 1; i < NF; i++) if ($i == "jump" || $i == "goto") jumps[ch] = jumps[ch] " " tbl "/" $(i + 1)
    }
    /(^|[[:space:]])(drop|reject)([[:space:]]|$)/ {
      if ($0 ~ /ct state invalid/) next
      if ($0 ~ /(^|[[:space:]])saddr[[:space:]]/ && $0 !~ /(^|[[:space:]])saddr[[:space:]]+!=/) next
      dropper[ch] = 1
    }
    END {
      for (c in input) if (filters(c, 0)) exit 0
      exit 1
    }'
}

# iptables_input_filters -> reads `iptables -S INPUT` (or ip6tables); exits 0 on
# a DROP/REJECT policy or rule. Ignored: a lone "--ctstate INVALID -j DROP" and
# ban lists, i.e. rules restricted to listed sources ("-s ADDR",
# "-m set --match-set NAME src", as fail2ban and CrowdSec add). A negated
# source ("! -s NET -j DROP") is an allowlist and counts.
iptables_input_filters() {
  awk '
    /^-P INPUT (DROP|REJECT)/ { f = 1 }
    /^-A INPUT / && / -j (DROP|REJECT)( |$)/ {
      if ($0 ~ /--(ct)?state INVALID /) next
      neg = ($0 ~ / ! -s / || $0 ~ / ! --match-set /)
      src = ($0 ~ / -s [^ ]+/ || $0 ~ / --match-set [^ ]+ src/)
      if (src && !neg) next
      f = 1
    }
    END { exit !f }'
}

# fw_banners -> reads nft and/or iptables rules on stdin; prints which IP ban
# tools left rules there ("fail2ban", "crowdsec", "fail2ban crowdsec" or "").
fw_banners() {
  awk '
    /^[[:space:]]*table[[:space:]]+[a-z0-9]+[[:space:]]+f2b-/ || / -j f2b-/ || /--match-set f2b-/ { f2b = 1 }
    /^[[:space:]]*table[[:space:]]+[a-z0-9]+[[:space:]]+crowdsec/ || /--match-set crowdsec/ || / -j CROWDSEC/ { cs = 1 }
    END {
      out = ""
      if (f2b) out = "fail2ban"
      if (cs) out = out (out == "" ? "" : " ") "crowdsec"
      print out
    }'
}

# detect_firewall -> sets FW_ACTIVE to the first frontend that filters INPUT,
# and FW_BANNERS to the IP ban tools seen in the rules (they are not firewalls).
detect_firewall() {
  FW_BANNERS=""
  if [ "$IS_ROOT" -ne 1 ]; then
    if unit_active firewalld; then FW_ACTIVE="firewalld"; else FW_ACTIVE="unknown"; fi
    return
  fi
  if fx_have UFW_STATUS ufw && fx UFW_STATUS ufw status | grep -q '^Status: active'; then FW_ACTIVE="ufw"; return; fi
  if fx_have FIREWALLD_STATE firewall-cmd && [ "$(fx FIREWALLD_STATE firewall-cmd --state)" = "running" ]; then FW_ACTIVE="firewalld"; return; fi
  local nft_rs="" ipt_rs=""
  if fx_have NFT nft; then nft_rs="$(fx NFT nft list ruleset)"; fi
  if fx_have IPTABLES_INPUT iptables; then ipt_rs="$(fx IPTABLES_INPUT iptables -S INPUT)"; fi
  FW_BANNERS="$(printf '%s\n%s\n' "$nft_rs" "$ipt_rs" | fw_banners)"
  if [ -n "$nft_rs" ] && printf '%s\n' "$nft_rs" | nft_input_filters; then FW_ACTIVE="nftables"; return; fi
  if [ -n "$ipt_rs" ] && printf '%s\n' "$ipt_rs" | iptables_input_filters; then FW_ACTIVE="iptables"; return; fi
  FW_ACTIVE="none"
}

detect_all() {
  detect_os; detect_pkg; detect_init; detect_virt; detect_provider; detect_firewall
}
