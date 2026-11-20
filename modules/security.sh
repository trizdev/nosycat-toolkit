#!/usr/bin/env bash
# modules/security.sh - brute-force protection, MAC, permissions, SUID, mounts.
# shellcheck shell=bash

# Basenames of SUID binaries shipped by mainstream distros.
_SUID_KNOWN=" su sudo sudoedit passwd chsh chfn newgrp gpasswd chage expiry mount umount ping ping6 pkexec
 fusermount fusermount3 ssh-keysign dbus-daemon-launch-helper polkit-agent-helper-1 Xorg.wrap unix_chkpwd
 pam_timestamp_check crontab at userhelper staprun ntfs-3g snap-confine sg doas traceroute6.iputils
 mount.nfs mount.cifs mount.ecryptfs_private pppd chrome-sandbox ksu newuidmap newgidmap write
 lxc-user-nic usernetctl grub2-set-bootflag sudoreplay bbsuid busybox cockpit-session vmware-user-suid-wrapper
 Xorg arping traceroute mtr-packet chromium-sandbox dmcrypt-get-device "

# _pkg_owner_tool -> name of the tool that maps a file to its package, if any.
_pkg_owner_tool() {
  case "$PKG_MGR" in
    apt-get) have dpkg && echo dpkg ;;
    dnf|yum|zypper) have rpm && echo rpm ;;
    apk) have apk && echo apk ;;
    pacman) have pacman && echo pacman ;;
    *) return 1 ;;
  esac
}

# pkg_owns PATH -> true when an installed package owns PATH. On merged-/usr
# systems dpkg may know /usr/bin/x as /bin/x, so both spellings are tried.
pkg_owns() {
  local p="$1" alt=""
  case "$p" in /usr/bin/*|/usr/sbin/*|/usr/lib/*|/usr/lib64/*) alt="${p#/usr}" ;; esac
  case "$(_pkg_owner_tool)" in
    dpkg) q dpkg -S "$p" >/dev/null || { [ -n "$alt" ] && q dpkg -S "$alt" >/dev/null; } ;;
    rpm) q rpm -qf "$p" >/dev/null || { [ -n "$alt" ] && q rpm -qf "$alt" >/dev/null; } ;;
    apk) q apk info --who-owns "$p" | grep -q 'is owned by' ;;
    pacman) q pacman -Qo "$p" >/dev/null ;;
    *) return 1 ;;
  esac
}

mod_security() {
  # SEC-001 brute-force protection
  if unit_active fail2ban || { have fail2ban-client && [ "$IS_ROOT" -eq 1 ] && q fail2ban-client ping | grep -q pong; }; then
    ok SEC-001 "fail2ban active" ""
  elif unit_active crowdsec || { have cscli && [ "$IS_ROOT" -eq 1 ] && q cscli version >/dev/null; }; then
    ok SEC-001 "CrowdSec active" ""
  elif have fail2ban-client || have cscli; then
    warn SEC-001 "fail2ban/CrowdSec installed but not running" "SSH and web logins are not rate-limited" "sudo systemctl enable --now fail2ban   # or crowdsec"
  else
    warn SEC-001 "no fail2ban or CrowdSec" "nothing bans hosts that brute-force SSH or web logins" "install fail2ban (sshd jail is enabled by default on Debian/Ubuntu) or CrowdSec"
  fi

  # SEC-002 mandatory access control
  if [ "$VIRT_KIND" = "container" ]; then
    skip SEC-002 "SELinux/AppArmor" "controlled by the container host"
  elif have getenforce; then
    local se
    se="$(q getenforce)"
    case "$se" in
      Enforcing) ok SEC-002 "SELinux enforcing" "" ;;
      Permissive) warn SEC-002 "SELinux permissive" "policy violations are logged but not blocked" "sudo setenforce 1 && sudo sed -i 's/^SELINUX=.*/SELINUX=enforcing/' /etc/selinux/config" ;;
      *) warn SEC-002 "SELinux disabled" "RHEL-family hardening relies on SELinux; re-enabling later needs a full relabel" "set SELINUX=enforcing in /etc/selinux/config, touch /.autorelabel and reboot" ;;
    esac
  elif [ -r /sys/module/apparmor/parameters/enabled ] && [ "$(cat /sys/module/apparmor/parameters/enabled)" = "Y" ]; then
    local prof=""
    if [ "$IS_ROOT" -eq 1 ] && have aa-status; then prof="$(q aa-status | awk '/profiles are in enforce mode/{print $1; exit}')"; fi
    ok SEC-002 "AppArmor enabled${prof:+ ($prof profiles enforcing)}" ""
  else
    case "$OS_FAMILY" in
      alpine|arch) ok SEC-002 "no SELinux/AppArmor" "not enabled by default on $OS_FAMILY" ;;
      *) warn SEC-002 "no SELinux or AppArmor active" "a compromised service is not confined by any MAC policy" "Debian/Ubuntu: sudo apt install apparmor apparmor-utils; RHEL: enable SELinux" ;;
    esac
  fi

  # SEC-003 world-writable files in key directories
  local dirs=() d ww=() wwd=()
  for d in /etc /usr/bin /usr/sbin /usr/local/bin /usr/local/sbin /usr/lib/systemd/system /etc/systemd/system /var/www /opt /srv /root; do
    [ -d "$d" ] && dirs+=("$d")
  done
  if [ "$IS_ROOT" -ne 1 ]; then
    skip SEC-003 "world-writable files" "needs root to search all key directories"
  else
    mapfile -t ww < <(t 60 find "${dirs[@]}" -xdev -type f -perm -0002 2>/dev/null | head -n 50)
    mapfile -t wwd < <(t 60 find "${dirs[@]}" -xdev -type d -perm -0002 ! -perm -1000 2>/dev/null | head -n 50)
    ww+=("${wwd[@]}")
    if [ "${#ww[@]}" -gt 0 ] && [ -n "${ww[0]}" ]; then
      local critical=0 x
      for x in "${ww[@]}"; do case "$x" in /etc/*|/usr/*|/root/*) critical=1 ;; esac; done
      if [ "$critical" -eq 1 ]; then
        fail SEC-003 "world-writable paths in system dirs: $(trunc_list 4 "${ww[@]}")" "any local user or compromised service can modify system config or binaries" "sudo chmod o-w PATH"
      else
        warn SEC-003 "world-writable paths: $(trunc_list 4 "${ww[@]}")" "any local user or compromised web app can modify them" "sudo chmod o-w PATH"
      fi
    else
      ok SEC-003 "no world-writable files in key directories" ""
    fi
  fi

  # SEC-004 SUID binaries not owned by a package (name list only as a fallback)
  if [ "$IS_ROOT" -ne 1 ]; then
    skip SEC-004 "unexpected SUID binaries" "needs root for a complete search"
  else
    local s base odd=() bad=() known=" ${_SUID_KNOWN//$'\n'/ } " how="package database"
    _pkg_owner_tool >/dev/null || how="name list (no package ownership tool for $PKG_MGR)"
    while IFS= read -r s; do
      [ -z "$s" ] && continue
      base="${s##*/}"
      case "$s" in /tmp/*|/var/tmp/*|/dev/shm/*|/home/*|/var/www/*) bad+=("$s"); continue ;; esac
      if _pkg_owner_tool >/dev/null; then
        pkg_owns "$s" && continue
      else
        case "$known" in *" $base "*) continue ;; esac
      fi
      odd+=("$s")
    done < <(if fx_set SUID; then fx SUID; else t 90 find / -xdev \( -path /proc -o -path /sys -o -path /run \) -prune -o -type f -perm -4000 -print 2>/dev/null; fi)
    if [ "${#bad[@]}" -gt 0 ]; then
      fail SEC-004 "SUID binaries in writable/user locations: $(trunc_list 4 "${bad[@]}")" "classic privilege-escalation backdoor" "sudo chmod u-s PATH and investigate how it got there"
    elif [ "${#odd[@]}" -gt 0 ]; then
      warn SEC-004 "SUID binaries not owned by any package: $(trunc_list 5 "${odd[@]}")" "each SUID root binary is a privilege-escalation candidate; one that no package installed (checked with the $how) needs an explanation" "dpkg -S PATH  /  rpm -qf PATH; remove the bit if unneeded: sudo chmod u-s PATH"
    else
      ok SEC-004 "no unexpected SUID binaries on /" "checked against the $how"
    fi
  fi

  # SEC-005 /tmp mount options. /dev/shm without noexec is the default on
  # Debian/Ubuntu and many others, so it is reported in the detail, not as a WARN.
  local opts mp tmp_issue="" shm_note=""
  for mp in /tmp /dev/shm; do
    opts="$(awk -v m="$mp" '$2==m{print $4}' "${NOSY_PROC_MOUNTS:-/proc/mounts}" 2>/dev/null | tail -n1)"
    case "$mp:,$opts," in
      /tmp:,,) tmp_issue="/tmp is not a separate mount" ;;
      /tmp:*,noexec,*) ;;
      /tmp:*) tmp_issue="/tmp is mounted without noexec" ;;
      /dev/shm:*,noexec,*) ;;
      /dev/shm:*) shm_note="/dev/shm allows exec (distro default); harden with 'tmpfs /dev/shm tmpfs defaults,nosuid,nodev,noexec 0 0' if nothing needs it" ;;
    esac
  done
  if [ "$VIRT_KIND" = "container" ]; then
    skip SEC-005 "/tmp noexec" "mounts managed by the container runtime"
  elif [ -n "$tmp_issue" ]; then
    warn SEC-005 "temp dir allows execution: $tmp_issue" "web exploits typically drop and run payloads from /tmp (note: some installers need exec on /tmp)${shm_note:+; also: $shm_note}" "add 'tmpfs /tmp tmpfs defaults,nosuid,nodev,noexec 0 0' to /etc/fstab (or systemctl enable tmp.mount) and reboot"
  else
    ok SEC-005 "/tmp mounted noexec" "$shm_note"
  fi

  # SEC-006 fstab entries that can block boot
  local fstab="${NOSY_FSTAB:-/etc/fstab}"
  if [ ! -r "$fstab" ]; then
    skip SEC-006 "fstab nofail" "/etc/fstab not readable"
  else
    local spec mnt fs fo risky=() net=()
    while read -r spec mnt fs fo _; do
      case "$spec" in ''|\#*) continue ;; esac
      case "$mnt" in /|/boot|/boot/efi|/efi|/usr|/var|/home|none|swap) continue ;; esac
      case "$fs" in swap|tmpfs|proc|sysfs|devpts|devtmpfs|efivarfs|bind) continue ;; esac
      case ",$fo," in *,bind,*|*,noauto,*) continue ;; esac
      case "$fs" in nfs|nfs4|cifs|smb3|sshfs|fuse.sshfs|glusterfs|ceph)
        case ",$fo," in *,_netdev,*) ;; *) net+=("$mnt") ;; esac ;;
      esac
      case ",$fo," in *,nofail,*|*x-systemd.automount*) ;; *) risky+=("$mnt ($fs)") ;; esac
    done <"$fstab"
    if [ "${#risky[@]}" -gt 0 ] || [ "${#net[@]}" -gt 0 ]; then
      local title=""
      [ "${#risky[@]}" -gt 0 ] && title="data mounts without nofail: $(join ', ' "${risky[@]}")"
      [ "${#net[@]}" -gt 0 ] && title="${title:+$title; }network mounts without _netdev: $(join ', ' "${net[@]}")"
      warn SEC-006 "$title" "if that volume is detached or renamed (common with block storage), boot stops in emergency mode and SSH never comes up" "add 'nofail' (and '_netdev' for network filesystems) to the options column; mount by UUID=; test with: sudo mount -a"
    else
      ok SEC-006 "no fstab data mounts that can block boot" ""
    fi
  fi
}
