# checks

Every check `nosycat.sh` runs. **Severity** is the worst status a check can return; `SKIP` is used whenever a check does not apply (tool not installed, inside a container, not root). `INFO` is a note about the run itself (ENV-006, not root) and never affects the exit code. `IGNORED` replaces a `WARN`/`FAIL` you accepted in an ignore file (see the end of this page). With `-q` / `--problems-only` only `WARN`/`FAIL` checks are printed. The JSON format is described in [`json.md`](json.md). Fix commands are suggestions printed by the tool. nosycat never runs them.

#### environment

| id | what | why it matters | severity | fix |
|---|---|---|---|---|
| ENV-001 | distribution from `/etc/os-release` | distro family drives package, firewall and path logic | WARN | run on a supported distro |
| ENV-002 | virtualization (VM, bare metal, container/LXC) | inside a container, kernel, firewall, swap and boot checks describe the host | WARN | run nosycat on the host |
| ENV-003 | provider hint (DMI, cloud-init, hostname) | reminds you that provider firewalls/security groups are invisible from inside | info | none |
| ENV-004 | package manager (apt, dnf/yum, apk, pacman, zypper) | update checks depend on it | WARN | none |
| ENV-005 | init system (systemd, OpenRC, other) | service checks depend on it | info | none |
| ENV-006 | running as root | as non-root, shadow, firewall rules, `sshd -T` and process names are hidden. A note about the run, not the server: `INFO`, never in "fix first" or the exit code | INFO | `sudo ./nosycat.sh` |

#### cloud_init

| id | what | why it matters | severity | fix |
|---|---|---|---|---|
| CLD-001 | hostname is not a provider default (`vmi123`, `ip-10-0-0-1`, `ubuntu-s-1vcpu…`) | generic names make logs and alerts ambiguous | WARN | `hostnamectl set-hostname web-01.example.com` |
| CLD-002 | `cloud-init status` is `done` | errors mean users, keys or packages from user-data may be missing | FAIL | `cloud-init status --long` |
| CLD-003 | default image users (`ubuntu`, `ec2-user`, `rocky`…) still have a login shell | well-known usernames are brute-forced first | WARN | `usermod -L -s /usr/sbin/nologin USER` |
| CLD-004 | `sshd_config.d/*.conf` drop-in sets `PasswordAuthentication yes` **and** that is the effective value (`sshd -T`, or the parsed config with first-value-wins). A drop-in `yes` overridden by an earlier `no` (e.g. `00-hardening.conf`) is OK | cloud-init drop-ins override `sshd_config`, so editing it alone does nothing | WARN | edit the drop-in, reload sshd (`ssh` on Debian/Ubuntu, `sshd` on RHEL, `rc-service sshd` on OpenRC) |
| CLD-005 | keys in `/root/.ssh/authorized_keys` | deploy-time keys tend to stay forever | WARN | `ssh-keygen -lf /root/.ssh/authorized_keys` |

#### system

| id | what | why it matters | severity | fix |
|---|---|---|---|---|
| SYS-001 | hostname resolves (`getent hosts`) | `sudo: unable to resolve host`, mail and Java services fail | WARN | add `127.0.1.1 HOSTNAME` to `/etc/hosts` |
| SYS-002 | timezone set | ambiguous log timestamps and cron times | WARN | `timedatectl set-timezone UTC` |
| SYS-003 | clock synchronized (timedatectl / chrony) | drift breaks TLS, TOTP and log correlation | WARN | `timedatectl set-ntp true` or install chrony |
| SYS-004 | UTF-8 locale, no locale errors | perl/apt warnings, broken non-ASCII handling | WARN | `localectl set-locale LANG=C.UTF-8` |
| SYS-005 | swap present on hosts with < 8 GiB RAM | memory spikes hit the OOM killer instead of slowing down | WARN | create a swapfile |
| SYS-006 | `vm.swappiness` ≤ 60 | high values push app memory to disk early | WARN | `vm.swappiness=10` in sysctl.d |
| SYS-007 | disk usage per filesystem (warn 80%, fail 90%) | full disks corrupt databases and stop logging | FAIL | find large dirs with `du` |
| SYS-008 | inode usage (warn 80%, fail 90%) | "No space left on device" with free bytes | FAIL | find dirs with many files |
| SYS-009 | open-files hard limit ≥ 65536 | "Too many open files" under load | WARN | `LimitNOFILE=` in the unit or limits.conf |
| SYS-010 | OOM-killer events in the last 7 days | services may be dying and restarting silently | WARN | `journalctl -k \| grep -i 'killed process'` |
| SYS-011 | available RAM (warn < 20%, fail < 10%) | no headroom for spikes | FAIL | `ps aux --sort=-rss` |
| SYS-012 | 5-min load vs vCPUs (warn ≥ 1x, fail ≥ 2x) | saturation, I/O wait or provider CPU steal | FAIL | `top` (check `%st`, `%wa`) |

#### access

| id | what | why it matters | severity | fix |
|---|---|---|---|---|
| SSH-001 | sshd config readable (`sshd -T` as root, parsed config otherwise) | effective values include drop-ins and defaults | info | run as root |
| SSH-002 | `PasswordAuthentication no` (and no PAM keyboard-interactive) | password SSH is brute-forced within minutes | FAIL | `PasswordAuthentication no`, reload sshd |
| SSH-003 | `PermitRootLogin` | `yes` = root by password; `prohibit-password` = root by key | FAIL | `PermitRootLogin no` after creating a sudo user |
| SSH-004 | `PermitEmptyPasswords no` | accounts without password could log in | FAIL | `PermitEmptyPasswords no` |
| SSH-005 | SSH port(s): every `Port` and `ListenAddress host:port` | informational; port 22 is fine with key-only auth | info | none |
| SSH-006 | a non-root member of sudo/wheel/admin, or a full sudoers grant (`user ALL=... ALL` or `%group ALL=... ALL`, in `/etc/sudoers` and `/etc/sudoers.d`) exists. Without root the sudoers files are unreadable, so no admin-group member is a SKIP, not a WARN | no audit trail; root login cannot be disabled | WARN | `adduser deploy && usermod -aG sudo deploy` |
| SSH-007 | home, `~/.ssh`, `authorized_keys` not group/world-writable, correct owner | StrictModes silently ignores keys → lockout | FAIL | `chmod 700 ~/.ssh; chmod 600 ~/.ssh/authorized_keys` |
| SSH-008 | login accounts that never logged in (`lastlog`/`lastlog2`) | forgotten accounts are attack surface | WARN | lock or remove the account |
| SSH-009 | accounts with an empty password in `/etc/shadow` | console/su login without password | FAIL | `passwd -l USER` |

#### network

| id | what | why it matters | severity | fix |
|---|---|---|---|---|
| NET-001 | sockets on `0.0.0.0` / `::` / public IPs, excluding SSH (all its ports) and DHCP. A web server (nginx, apache, caddy, traefik, haproxy, lighttpd, envoy) on tcp 80/443 is expected and only listed in the detail | everything bound there is internet-reachable unless filtered | WARN | bind to 127.0.0.1 or filter |
| NET-002 | host firewall active (ufw, firewalld, nftables, iptables). For nftables/iptables only chains hooked on **input** count: a `policy drop`, or a drop/reject rule in that chain or in a chain it jumps to. Drops elsewhere (Docker's `DOCKER-ISOLATION-*` on FORWARD), a lone `ct state invalid drop`, ban lists that only drop listed sources (`ip saddr @set`, `-m set --match-set NAME src`, `-s IP -j REJECT`) and the fail2ban/CrowdSec tables (`f2b-*`, `crowdsec*`) do not; the detail says when fail2ban or CrowdSec was seen | FAIL when services are exposed and nothing filters them | FAIL | `ufw allow OpenSSH && ufw enable` |
| NET-003 | IPv6 covered by the firewall when a global IPv6 exists | ufw `IPV6=no` or ip-only nft tables leave IPv6 wide open | FAIL | `IPV6=yes` / `table inet` |
| NET-004 | nameserver configured and `example.com` resolves | updates, ACME and outbound APIs fail | FAIL | check resolv.conf / resolved |
| NET-005 | `net.ipv4.ip_forward` (expected with Docker/VPN) | a plain VPS should not route packets | WARN | `net.ipv4.ip_forward=0` |
| NET-006 | `net.ipv4.tcp_syncookies=1` | SYN-flood resilience | WARN | `net.ipv4.tcp_syncookies=1` |
| NET-007 | `accept_redirects=0` (all, default) | ICMP redirects can re-route traffic | WARN | set both to 0 |

#### updates

| id | what | why it matters | severity | fix |
|---|---|---|---|---|
| UPD-001 | pending updates from local metadata (security count where available); SKIP when the query fails or times out, except zypper exit 106 with listed updates (marked partial) | fresh images are often weeks behind | FAIL (security) | `apt full-upgrade` / `dnf upgrade` / `apk upgrade` / `pacman -Syu` |
| UPD-002 | unattended-upgrades / dnf-automatic enabled | unattended servers fall behind on fixes | WARN | install and enable the tool |
| UPD-003 | reboot required (`/var/run/reboot-required`, `needs-restarting -r`, running kernel removed) | fixes not active; new kernel modules fail to load | WARN | reboot in a maintenance window |

#### docker

Skipped entirely when Docker is not installed.

| id | what | why it matters | severity | fix |
|---|---|---|---|---|
| DKR-001 | daemon reachable | containers will not start | WARN | `systemctl enable --now docker` |
| DKR-002 | members of the `docker` group | docker group = root | WARN | `gpasswd -d USER docker` |
| DKR-003 | privileged containers | isolation disabled | FAIL | use `cap_add`/`devices` |
| DKR-004 | `docker.sock` mounted into containers | socket access = root on host | WARN | socket proxy or remove |
| DKR-005 | ports published on `0.0.0.0`/`::` | Docker DNATs published ports before INPUT, bypassing ufw/firewalld/nftables/iptables | FAIL (with an active host firewall); WARN without one (NET-002 already FAILs) | publish `127.0.0.1:PORT:PORT`, or filter in `DOCKER-USER` |
| DKR-006 | restart policy set | container stays down after reboot | WARN | `restart: unless-stopped` |
| DKR-007 | json-file log `max-size` (per container or daemon.json) | logs fill the disk | WARN | `log-opts` in daemon.json |

#### services

| id | what | why it matters | severity | fix |
|---|---|---|---|---|
| SVC-001 | failed systemd units (crashed OpenRC services) | broken config or missing dependency | WARN | `systemctl status UNIT` |
| SVC-002 | enabled long-running services that are inactive (oneshot, timer/socket-activated and condition-skipped units excluded) | expected to run, but down | WARN | start or disable it |
| SVC-003 | persistent journal | logs lost on reboot, crash cause unknown | WARN | `mkdir /var/log/journal` or `Storage=persistent` |
| SVC-004 | journal size cap (`SystemMaxUse`) | default 10% of fs (max 4G) is a lot on small disks | WARN | `SystemMaxUse=500M` |
| SVC-005 | logrotate installed and scheduled | `/var/log` grows forever | WARN | install / enable `logrotate.timer` |

#### web_tls

| id | what | why it matters | severity | fix |
|---|---|---|---|---|
| WEB-001 | `nginx -t` | next reload takes the site down | FAIL | fix the reported line |
| WEB-002 | nginx `sites-enabled/default` still enabled | IP scans and unknown Hosts hit the default site | WARN | remove the symlink |
| WEB-003 | `apachectl -t` / `httpd -t` | next reload fails | FAIL | fix the reported line |
| WEB-004 | certificates used by the **enabled** config (`nginx -T` as root, else `nginx.conf`, `conf.d`, `sites-enabled`; apache `sites-enabled`, `conf-enabled`, `conf.d`) expire in < 21 days (`CERT_WARN_DAYS`). `sites-available` is never read. Let's Encrypt lineages no enabled vhost uses are only a WARN | renewal is broken; expired = FAIL | FAIL | `certbot renew --dry-run`; `certbot delete` for leftovers |
| WEB-005 | certbot timer/cron present | certs silently expire after 90 days | WARN | `systemctl enable --now certbot.timer` |

#### security

| id | what | why it matters | severity | fix |
|---|---|---|---|---|
| SEC-001 | fail2ban or CrowdSec running | nothing bans brute-force sources | WARN | install fail2ban or CrowdSec |
| SEC-002 | SELinux enforcing / AppArmor enabled | compromised services are not confined | WARN | enable the distro's MAC |
| SEC-003 | world-writable files, and dirs without sticky bit, in `/etc`, `/usr/*bin`, systemd dirs, `/var/www`, `/opt`, `/srv`, `/root` | anyone can alter config or binaries | FAIL (system dirs) | `chmod o-w PATH` |
| SEC-004 | SUID binaries on `/` not owned by any package (`dpkg -S`, `rpm -qf`, `apk info --who-owns`, `pacman -Qo`; a built-in name list only when no such tool exists); SUID in `/tmp`, `/home`, `/var/www` | privilege escalation / backdoor | FAIL (writable dirs) | verify package, `chmod u-s` |
| SEC-005 | `/tmp` mounted `noexec`. `/dev/shm` without `noexec` is the Debian/Ubuntu default, so it is only noted in the detail, not a WARN | exploits drop and run payloads there | WARN | tmpfs with `noexec` |
| SEC-006 | fstab data mounts without `nofail`, network mounts without `_netdev` | a detached volume drops boot into emergency mode, no SSH | WARN | add `nofail` / `_netdev` |

#### databases

| id | what | why it matters | severity | fix |
|---|---|---|---|---|
| DB-001 | MySQL/MariaDB, PostgreSQL, Redis, MongoDB, Memcached, Elasticsearch, CouchDB, InfluxDB listening beyond loopback (default port or process name) | exposed databases are scanned and ransomed within hours; private-network = WARN | FAIL | bind to 127.0.0.1 and firewall |
| DB-002 | Redis answers `PING` without auth, probed on the host:port it actually listens on. OK only on a `NOAUTH` reply; `DENIED` (protected mode, no password) is a WARN; no connection is a SKIP with the reason | data read/write, file writes via `CONFIG SET` | FAIL (if public) | `requirepass` / ACLs |

#### backup

Read-only and secret-free: nosycat never runs a backup tool, and never asks for or reads a password, env file, keyring or repository key. Cron lines and unit files are scanned for a backup command and a local repository path; the lines themselves are never printed. Provider snapshots (Hetzner, DigitalOcean, Contabo…) cannot be seen from inside the VM: if they are your backup, accept BKP-001 in `.nosycat.ignore` with an `until` date.

| id | what | why it matters | severity | fix |
|---|---|---|---|---|
| BKP-001 | a backup tool is installed: restic, borg/borgmatic, rsnapshot, timeshift, duplicity, duplicati, kopia | no backup is the problem you only find out about during the outage | WARN | install restic or borg with a repository off the server |
| BKP-002 | the backup runs by itself: `/etc/crontab`, `/etc/cron.d`, `/etc/cron.{hourly,daily,weekly,monthly}`, the cron spool, enabled systemd timers (a `*.wants/` link) whose name or service mentions a backup tool, timeshift's own schedule, duplicati/kopia server units. Commented-out lines and trailing ` # comments` do not count. As non-root, an empty result is a SKIP (root's crontab is not readable) | a backup that runs by hand stops running | WARN | a systemd service + timer, or a `/etc/cron.d` entry |
| BKP-003 | age of the newest backup, from metadata readable without a password: restic cache (`~/.cache/restic/*/snapshots`) or a local repo's `snapshots/`, borg `~/.config/borg/security/*/manifest-timestamp`, rsnapshot `<snapshot_root>/<interval>.0`, timeshift snapshot names, duplicity cache. kopia and duplicati keep this behind the password or in their database, so it is a SKIP with the reason. The age is compared in seconds (7 days and 5 hours is over a 7-day limit); timeshift names are read as local time. Caveat: the restic cache and borg's `manifest-timestamp` are also refreshed by read-only commands (`restic snapshots`, `restic check`, `borg list`), so a monitoring job that only lists snapshots can make a failing backup look fresh; check the job's own log too | a job that fails quietly looks exactly like one that works | WARN (older than `--backup-max-age`, default 7 days) | read the job's log, run it once by hand, test a restore |
| BKP-004 | where local backups live: rsnapshot root, local restic/borg repo, timeshift snapshots on the same filesystem as `/`. OK when a remote repository is in use or the target is a separate filesystem; symlinks are followed (`stat -L`); SKIP when the destination is not visible or its filesystem cannot be determined (never counted as separate) | a copy on the same disk dies with the disk, and with the server | WARN | send a copy off the server (storage box, S3, another host) |

#### ignoring accepted findings

Put check ids in `.nosycat.ignore` inside the state dir (`/var/lib/nosycat/.nosycat.ignore` as root) or pass `--ignore FILE` (repeatable). Matching `WARN`/`FAIL` results are reported as `IGNORED` with the reason, keep their original status in JSON (`original_status`, `ignore_reason`, `ignore_until`), and do not affect the exit code. `OK` and `SKIP` results are never changed.

```
# one per line: ID, ID: reason, or a glob; optionally "until YYYY-MM-DD"
# "#" starts a comment only at the start of a line or right after the id
NET-001: grafana on 3000 is behind the provider firewall
SEC-005: installer needs exec until 2027-01-31
BKP-001: provider snapshots, daily until 2027-06-30
SNP-* until 2026-12-31
SSH-008: ex-contractor account, see ticket #4512 until 2027-03-01
```

A `#` inside a reason is part of the reason (`ticket #4512` above). `until` is matched in any case and must be followed by a valid `YYYY-MM-DD`; `until` with no date, or an invalid date, prints a warning on stderr and the entry is skipped, so the finding shows.

- **expiry:** `until YYYY-MM-DD` is the last day the entry applies. From the next day the check shows its real status again, its detail starts with `ignore expired DATE (reason)`, it counts for the exit code, JSON adds `ignore_expired` (and `summary.ignore_expired`), and the summary lists the expired ids. The date is the server's local date.
- **no expiry:** the entry is permanent, and the text summary adds a gentle tip to set one, so accepted risks come back for review instead of being swept under the rug.
- **invalid dates** (`2027-02-30`, `31/01/2027`) print a warning on stderr and the entry is skipped, so the finding shows; the run continues. `until` only counts when the word after it starts with a digit, so a reason like `open until we move to the vpn` stays a reason.

#### snapshot (`--diff`)

`--snapshot` stores a baseline (default `/var/lib/nosycat/baseline`, mode 0700). `--diff` compares the live server to it. Each changed category is a WARN listing up to 5 added/removed entries.

| id | category |
|---|---|
| SNP-000 | baseline metadata (date) |
| SNP-001 | listening sockets (proto, address:port, process) |
| SNP-002 | enabled services, timers, sockets |
| SNP-003 | user accounts (name, uid, shell) |
| SNP-004 | members of sudo/wheel/admin/docker/root groups |
| SNP-005 | cron files (sha256) and systemd timers |
| SNP-006 | SSH authorized keys (sha256 per key, per user) |
| SNP-007 | installed package count |
| SNP-008 | containers (name, image) |
