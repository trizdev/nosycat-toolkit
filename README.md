<div align="center">
<pre>
           .---.                     
         _/_____\_     ________      
          ( o.o )     |$ sniff |     
           > ^ <      |$ _     |     
          /     \_____|________|     
         (__| |__)   /________/      
                                     
.·:*¨¨* ❀ nosycat-toolkit ❀ *¨¨*:·.  
   post-deploy check-up for linux vps
         ~ sniffing for clues ~      
</pre>
</div>

<h1 align="center">nosycat-toolkit</h1>

<p align="center"><i>a curious little cat that sniffs your freshly deployed server for the things that bite later</i></p>

<p align="center">
  <img src="https://img.shields.io/badge/bash-4%2B-C9A2A6?style=flat-square&logo=gnubash&logoColor=white" alt="bash 4+">
  <img src="https://img.shields.io/badge/mode-read--only-A3B18A?style=flat-square" alt="read-only">
  <img src="https://img.shields.io/badge/debian%20%C2%B7%20rhel%20%C2%B7%20alpine%20%C2%B7%20arch-B8A9C9?style=flat-square&logo=linux&logoColor=white" alt="distros">
  <a href="https://github.com/trizdev/nosycat-toolkit/actions/workflows/ci.yml"><img src="https://img.shields.io/github/actions/workflow/status/trizdev/nosycat-toolkit/ci.yml?branch=main&style=flat-square&label=shellcheck%20%2B%20tests" alt="ci status"></a>
  <img src="https://img.shields.io/badge/license-MIT-E9D8A6?style=flat-square" alt="MIT license">
</p>

<p align="center">.·:*¨¨* ❀ *¨¨*:·.</p>

#### what is it

You just deployed a VPS. It boots, SSH works, the app is up. Then, weeks later, a disk fills with container logs, a Redis instance ends up on a scanner list, a detached volume stops the server at boot, or Docker quietly publishes a port that ufw was supposed to block.

`nosycat.sh` is a single Bash script that runs right after deploy and flags those problems while they are still cheap to fix. Each check returns `OK`, `WARN`, `FAIL` or `SKIP`, a one-line reason, and a suggested fix command (`INFO` is a note about the run itself, like running without root, and never changes the exit code). It works on Debian/Ubuntu, RHEL/Rocky/Alma, Alpine and Arch, on any provider (Hetzner, Contabo, DigitalOcean, AWS, OVH, Vultr…), and needs nothing beyond Bash 4 and standard userland tools.

<p align="center">.·:*¨¨* ❀ *¨¨*:·.</p>

#### scope

**in scope**

- one Linux server, checked locally, right after deploy or after a big change
- configuration that commonly causes outages, lockouts or exposure: SSH, firewall, listeners, updates, Docker, services, logs, TLS, mounts, databases
- whether a backup exists, runs by itself, is recent, and lives off the root disk
- a baseline snapshot and a diff, to see what changed since deploy
- reports for humans (text, Markdown) and machines (JSON, exit codes)

**out of scope**

- auto-fixing: nosycat prints fix commands, it never runs them
- continuous monitoring or alerting (use a monitoring stack or a HIDS such as Wazuh)
- intrusion forensics, malware or rootkit detection
- Windows and macOS
- provider-side settings (cloud firewalls, security groups), which are not visible from inside the VM

<p align="center">.·:*¨¨* ❀ *¨¨*:·.</p>

#### safety

- **read-only.** No service is restarted, no package installed, no config edited, no firewall rule touched. Package checks use local metadata (`apt-get -s`, `dnf check-update`, `apk version`).
- **only two opt-in writes:** `--snapshot` saves a baseline to its own state dir (`/var/lib/nosycat`, mode 0700), and `--output DIR` writes the report to the directory you choose.
- **never hangs.** Slow or network-bound commands run under `timeout` (default 10s, `--timeout` to change); missing tools are skipped.
- **no secrets read.** The backup module never runs a backup tool and never opens a password, env file or keyring; ages come from cache and snapshot metadata.
- **nothing leaves the server.** No network calls besides a DNS lookup of `example.com` and whatever your package manager does when queried.
- **works without root,** with reduced visibility: checks that need root are marked `SKIP` instead of guessing.

Read the code before running anything with `sudo`, this one included. It is about 3,000 lines of plain Bash. Found a security problem in nosycat itself? See [`SECURITY.md`](SECURITY.md).

<p align="center">.·:*¨¨* ❀ *¨¨*:·.</p>

#### quick start

Run a tagged release, not `main`: a release is a fixed, reviewed snapshot with a published checksum, while `main` can change under you between reading the code and running it with `sudo`.

```bash
VER=0.2.1
BASE=https://github.com/trizdev/nosycat-toolkit/releases/download/v$VER
curl -fsSLO "$BASE/nosycat-toolkit-$VER.tar.gz"
curl -fsSLO "$BASE/nosycat-toolkit-$VER.tar.gz.sha256"
sha256sum -c "nosycat-toolkit-$VER.tar.gz.sha256"     # must print: OK
tar xzf "nosycat-toolkit-$VER.tar.gz" && cd "nosycat-toolkit-$VER"
sudo ./nosycat.sh
```

Prefer a single file you can `scp` to the server? Each release also ships `nosycat.sh` with `lib/` and `modules/` inlined (built by `scripts/bundle.sh`, tested in CI to give the same output as the tree):

```bash
# on your machine
VER=0.2.1
BASE=https://github.com/trizdev/nosycat-toolkit/releases/download/v$VER
curl -fsSLO "$BASE/nosycat.sh" && curl -fsSLO "$BASE/nosycat.sh.sha256"
sha256sum -c nosycat.sh.sha256                        # must print: nosycat.sh: OK
scp nosycat.sh nosycat.sh.sha256 deploy@192.0.2.10:

# on the server
sha256sum -c nosycat.sh.sha256 && chmod +x nosycat.sh && sudo ./nosycat.sh
```

The checksum guards against a corrupted or swapped download; compare it with the one on the [release page](https://github.com/trizdev/nosycat-toolkit/releases) too. Hacking on it instead? `git clone` the repo and run `./nosycat.sh` from your checkout.

```bash
sudo ./nosycat.sh -q                                # only WARN/FAIL + the summary
sudo ./nosycat.sh --only access,network,docker     # just a few modules
sudo ./nosycat.sh --skip updates                    # everything but updates
sudo ./nosycat.sh --format json > report.json       # machine-readable
sudo ./nosycat.sh --format md --output ./reports    # markdown file in ./reports
sudo ./nosycat.sh --snapshot                        # right after deploy
sudo ./nosycat.sh --diff                            # later: what changed?
sudo ./nosycat.sh --color always | less -R          # keep the colors in a pager
sudo ./nosycat.sh --ascii                           # plain ASCII box and symbols
sudo ./nosycat.sh --only backup --backup-max-age 2  # nightly backups: warn after 2 days
```

<p align="center">.·:*¨¨* ❀ *¨¨*:·.</p>

#### sample output

> fabricated example for documentation (host `web-01.example.com`, address from the `192.0.2.0/24` documentation range). Abridged.

```
  v0.2.0 · host web-01.example.com · 2026-11-16 18:02 UTC · read-only
  note: running as deploy (not root), so some checks are SKIPped. use sudo for the full picture.

❀ environment
  [OK]   ENV-001  distribution: Ubuntu 24.04.1 LTS
  [OK]   ENV-002  virtualization: kvm (vm)
  [OK]   ENV-003  provider: hetzner
                  why: from dmi/hostname; remember provider-level firewalls/security groups are not visible from inside the VM
  [INFO] ENV-006  running as deploy (not root)
                  why: reduced visibility: firewall rules, shadow, sshd -T, other users' files and process names are hidden; affected checks are marked SKIP. run with sudo for the full picture

❀ cloud_init
  [OK]   CLD-002  cloud-init finished: done
  [WARN] CLD-004  sshd drop-in enables password auth: /etc/ssh/sshd_config.d/50-cloud-init.conf
                  why: provider/cloud-init drop-ins (e.g. 50-cloud-init.conf) are read before sshd_config and override it, so editing sshd_config alone does nothing
                  fix: sudo sed -i 's/^PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config.d/50-cloud-init.conf && sudo systemctl reload ssh

❀ system
  [WARN] SYS-005  no swap configured (1963 MiB RAM)
                  why: on small VPS a memory spike (apt, composer, builds) triggers the OOM killer instead of slowing down
                  fix: sudo fallocate -l 2G /swapfile && sudo chmod 600 /swapfile && sudo mkswap /swapfile && sudo swapon /swapfile

❀ access
  [FAIL] SSH-002  SSH password authentication is enabled
                  why: internet-facing SSH with passwords is brute-forced within minutes of deploy
                  fix: set PasswordAuthentication no (check sshd_config.d drop-ins too) && sudo systemctl reload ssh
  [OK]   SSH-006  non-root admin user(s): deploy

❀ network
  [IGN]  NET-001  1 service(s) listening on all interfaces: 3000/tcp(grafana)
                  why: ignored, was WARN: grafana is behind the provider firewall · anything bound to 0.0.0.0/:: is reachable from the internet unless a firewall blocks it
  [OK]   NET-002  host firewall active: ufw

❀ updates
  [WARN] UPD-001  14 pending updates (6 security)
                  why: security fixes are public, exploits follow within days
                  fix: sudo apt-get update && sudo apt-get upgrade

❀ docker
  [FAIL] DKR-005  ports published on all interfaces: grafana 3000>3000/tcp
                  why: Docker writes its own iptables rules, so these ports are public even if ufw denies them
                  fix: publish as '127.0.0.1:8080:80' behind a reverse proxy, or filter in the DOCKER-USER chain
  [WARN] DKR-007  json-file logs without size limit: grafana, app
                  why: container logs grow until the disk is full
                  fix: set log-opts max-size/max-file in /etc/docker/daemon.json

❀ services
  [WARN] SVC-004  journal has no size cap (SystemMaxUse)
                  why: ignore expired 2026-11-10 (journal cap on the todo list) · the default is 10% of the filesystem, up to 4G
                  fix: printf '[Journal]\nSystemMaxUse=500M\n' | sudo tee /etc/systemd/journald.conf.d/size.conf

❀ security
  [IGN]  SEC-005  /tmp is not mounted noexec
                  why: ignored, was WARN: installer needs exec (until 2027-01-31)

❀ databases
  [OK]   DB-001   databases bound to loopback only: postgresql on 127.0.0.1:5432

❀ backup
  [OK]   BKP-001  backup tools: restic
                  why: provider snapshots (Hetzner, DigitalOcean, Contabo...) cannot be seen from inside the VM; only tools on this server are checked
  [OK]   BKP-002  backup job scheduled
                  why: systemd restic-backup.timer
  [SKIP] BKP-003  age of the last backup
                  why: needs root to read root's backup caches and repositories
  [SKIP] BKP-004  backups stored off the root disk
                  why: backup destination not visible (remote, or set in a config nosycat does not read)

.·:*¨¨* ❀ *¨¨*:·.

  ╭─ summary ────────────────────────────────────── 41 checks ─╮
  │ ✗ 2 FAIL   ! 6 WARN   ✓ 26 OK   · 5 SKIP   ~ 2 IGN         │
  │ ███▓▓▓▓▓▓▓▓▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒░░░░░░░░░░ │
  ╰────────────────────────────────────────────────────────────╯

❀ by module
  environment ✓ ok                  cloud_init  ! 1 warn
  system      ! 1 warn              access      ✗ 1 fail
  network     ! 1 warn              updates     ! 1 warn
  docker      ✗ 1 fail ! 1 warn     services    ! 1 warn
  web_tls     ✓ ok                  security    ✓ ok
  databases   ✓ ok                  backup      ✓ ok

❀ fix first
  ✗ SSH-002  SSH password authentication is enabled
  ✗ DKR-005  ports published on all interfaces: grafana 3000>3000/tcp
  ! CLD-004  sshd drop-in enables password auth: /etc/ssh/sshd_config.d/50-clo…
  ! SYS-005  no swap configured (1963 MiB RAM)
  ! NET-005  net.ipv4.ip_forward=1
  ! UPD-001  14 pending updates (6 security)
  ! DKR-007  json-file logs without size limit: grafana, app
  ! SVC-004  journal has no size cap (SystemMaxUse)

  =x.x=  2 hard failure(s). fix the FAIL items first!
  4 of 5 skipped checks need root; run with sudo for the full picture.
  1 ignore expired: SVC-004. renew the date or fix it.
  tip: 1 ignore without an expiry; add "until YYYY-MM-DD" so accepted risks come back.
```

The second time you run it you usually want only what needs attention. `-q` / `--problems-only` prints the WARN and FAIL checks with their why and fix, then the same summary:

```
❀ nosycat-toolkit v0.2.0 · host web-01.example.com · 2026-11-16 18:02 UTC · problems only
  note: not root, some checks SKIP; sudo shows everything.

❀ access
  [FAIL] SSH-002  SSH password authentication is enabled
                  why: internet-facing SSH with passwords is brute-forced within minutes of deploy
                  fix: set PasswordAuthentication no (check sshd_config.d drop-ins too) && sudo systemctl reload ssh

❀ services
  [WARN] SVC-004  journal has no size cap (SystemMaxUse)
                  why: ignore expired 2026-11-10 (journal cap on the todo list) · the default is 10% of the filesystem, up to 4G
                  fix: printf '[Journal]\nSystemMaxUse=500M\n' | sudo tee /etc/systemd/journald.conf.d/size.conf

.·:*¨¨* ❀ *¨¨*:·.

  … the same summary card as above
```

In a terminal the summary card is colored with a pastel palette: rose FAIL, peach WARN, mint OK, lavender SKIP, a lilac box and a rainbow ❀ divider; the bar is split by status. Colors turn off by themselves when the output is piped or saved with `--output`, when `NO_COLOR` is set, or with `TERM=dumb`; `--color always|never` overrides that. The box, bar and symbols fall back to plain ASCII when the locale is not UTF-8, or with `--ascii`.

<p align="center">.·:*¨¨* ❀ *¨¨*:·.</p>

#### modules

| module | what it sniffs |
|---|---|
| `environment` | distro, VM/container/LXC, provider hint, package manager, init system, root or not |
| `cloud_init` | cloud-init errors, default provider hostname, default image users, sshd drop-ins re-enabling passwords, injected root keys |
| `system` | hostname resolution, timezone, NTP, locale, swap, swappiness, disk and inodes, open-files limit, OOM kills, RAM and load |
| `access` | effective sshd config (`sshd -T`), password and root login, port, non-root sudo user, `~/.ssh` permissions, unused accounts, empty passwords |
| `network` | listeners on `0.0.0.0`/`::`, host firewall, IPv6 without rules, DNS, `ip_forward`, SYN cookies, ICMP redirects |
| `updates` | pending (security) updates, unattended-upgrades / dnf-automatic, reboot required |
| `docker` | docker group, privileged containers, mounted `docker.sock`, ports bypassing ufw, restart policy, log size limits |
| `services` | failed units, enabled-but-dead services, persistent journal and size cap, logrotate |
| `web_tls` | `nginx -t`, default site, apache configtest, certificates expiring in < 21 days, certbot renewal timer |
| `security` | fail2ban / CrowdSec, SELinux / AppArmor, world-writable files, unexpected SUID, `/tmp` noexec, fstab `nofail` |
| `databases` | MySQL/MariaDB, PostgreSQL, Redis, MongoDB, Memcached, Elasticsearch… on non-loopback, Redis without auth |
| `backup` | restic, borg/borgmatic, rsnapshot, timeshift, duplicity, duplicati, kopia: installed, scheduled (cron, systemd timers), age of the last backup, stored off the root disk. Never reads a password |
| `snapshot` | `--snapshot` / `--diff`: listeners, services, users, admin groups, cron, authorized_keys, packages, containers |

Every check, with its id, rationale, severity and fix, is listed in [`docs/checks.md`](docs/checks.md).

<p align="center">.·:*¨¨* ❀ *¨¨*:·.</p>

#### output formats & exit codes

| `--format` | use |
|---|---|
| `text` | colored terminal output, printed as checks run, ending in a summary card: counts and a status bar, status by module, the top FAIL/WARN items to fix first and a verdict (default) |
| `md` | Markdown report with an environment table and one table per module (plain ASCII with `--ascii` or a non-UTF-8 locale) |
| `json` | `{schema_version, tool, version, host, problems_only, environment, summary, checks[]}`, one object per check with `id`, `module`, `status`, `title`, `detail`, `fix` (plus `original_status`, `ignore_reason` and `ignore_until` when ignored, `ignore_expired` when an ignore ran out). Fields and the stability policy: [`docs/json.md`](docs/json.md) |

**`-q` / `--problems-only`** works with every format: `text` prints only WARN/FAIL checks (with why and fix), a one-line banner and the summary; `md` keeps only the WARN/FAIL rows; `json` keeps only WARN/FAIL in `checks[]` and sets `"problems_only": true`. The summary counts and the exit code always cover every check.

**`schema_version`** (`"1"` today) is the first field of the JSON report. New fields, modules and check ids keep the same version; removing or renaming a field, changing a type or adding a `status` value bumps it. Pin it in your pipeline: `jq -e '.schema_version == "1"'`.

| exit code | meaning |
|---|---|
| `0` | everything OK (SKIPs, IGNOREDs and INFO notes do not count) |
| `1` | at least one WARN |
| `2` | at least one FAIL |
| `3` | usage error or missing baseline |

<p align="center">.·:*¨¨* ❀ *¨¨*:·.</p>

#### accepted findings (`.nosycat.ignore`)

Some WARNs are deliberate on your server. List them once and they stop turning every run into exit 1:

```
# /var/lib/nosycat/.nosycat.ignore  (read automatically; or pass --ignore FILE)
NET-001: grafana on 3000 is behind the provider firewall
SEC-005: installer needs exec until 2027-01-31
BKP-001: provider snapshots, daily until 2027-06-30
SNP-* until 2026-12-31
SSH-008: ex-contractor account, see ticket #4512 until 2027-03-01
```

One check id per line, optionally `: reason`; globs like `SNP-*` work. Matching WARN/FAIL results are shown as `IGNORED` with your reason, kept in the JSON with their original status, and left out of the exit code. A web server on 80/443 and `/dev/shm` without `noexec` (the Debian default) no longer warn, so most servers need few entries.

An accepted risk should come back for review, so an entry can end in **`until YYYY-MM-DD`** (with or without a reason). It applies through that day; from the next day the check shows its real status again with `ignore expired DATE (reason)` in its detail, counts for the exit code, and the summary lists it. Entries without a date stay permanent, and the summary gently suggests adding one. An invalid date (`2027-02-30`) or an `until` without a date prints a warning and skips that entry, so the finding shows. `until` is matched in any case.

`#` starts a comment only at the start of a line or right after the id (`SEC-00*   # globs work`); inside a reason it is kept as text, so `see ticket #4512 until 2027-03-01` keeps both the ticket number and the date.

<p align="center">.·:*¨¨* ❀ *¨¨*:·.</p>

#### using it with cron, ansible & wazuh

**cron:** weekly JSON report, kept locally:

```cron
0 6 * * 1  root  /opt/nosycat-toolkit/nosycat.sh --format json --output /var/log/nosycat >/dev/null 2>&1
```

**ansible:** run after provisioning and fail the play on `FAIL`:

```yaml
- name: nosycat post-deploy check-up
  ansible.builtin.command: /opt/nosycat-toolkit/nosycat.sh --format json
  register: nosy
  changed_when: false
  failed_when: nosy.rc >= 2
```

**wazuh:** point a `localfile` at the JSON reports so each run lands in the SIEM:

```xml
<localfile>
  <log_format>json</log_format>
  <location>/var/log/nosycat/*.json</location>
</localfile>
```

<p align="center">.·:*¨¨* ❀ *¨¨*:·.</p>

#### roadmap

- [x] config file to silence accepted findings (`.nosycat.ignore`)
- [ ] JSON lines output (one event per check) for SIEM ingestion
- [ ] Podman and rootless Docker checks
- [x] backup presence, schedule and age (restic, borg, rsnapshot, timeshift, duplicity, duplicati, kopia)
- [x] expiry dates for accepted findings (`until YYYY-MM-DD`)
- [x] `--problems-only` / `-q` lean output
- [ ] kernel hardening sysctl profile (`kptr_restrict`, `dmesg_restrict`, `rp_filter`)
- [ ] remote mode over SSH for several hosts
- [x] bats test suite with fixture configs

<p align="center">.·:*¨¨* ❀ *¨¨*:·.</p>

#### tests

The parsers and checks are tested with [bats](https://github.com/bats-core/bats-core) against fixture files (`tests/fixtures`: nft rulesets, `ss` output, `sshd -T`, certificates, mounts) and small fake commands (`tests/stubs`: `docker`, `redis-cli`, `dpkg`). The `NOSY_FX_*` (including `NOSY_FX_TODAY` / `NOSY_FX_NOW` for the clock), `NOSY_ETC` and `NOSY_FS` variables point nosycat at those fixtures; normal runs never set them.

```bash
bats tests/
```

CI runs lint, a non-root runner bats suite, and an Ubuntu, Debian, Rocky Linux and Alpine matrix independently. Each container is prepared once; CLI smoke tests run after a bats failure when container preparation succeeds and the run is not cancelled, and JSON validation runs if smoke succeeds. Every failure still fails CI.

For optional checks of a specific revision, manually dispatch `ci.yml` with `target_sha` set to the source commit's full 40-character lowercase hexadecimal SHA available to checkout in that repository. The dispatch-enabled workflow must be on the [default branch](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/manually-run-a-workflow). The selected workflow branch/tag supplies the workflow; `target_sha` selects the source checkout, while push and pull request runs keep their normal checkout behavior. To compare source revisions, keep the selected workflow ref at the same commit between runs and check the job summaries for the same workflow SHA, the intended source SHAs and recorded step outcomes.

A check got it wrong on your server? Open a [false positive issue](https://github.com/trizdev/nosycat-toolkit/issues/new?template=false_positive.yml): it asks for the check id, the distro and the `--format json --only <module>` output (redacted).

<p align="center">.·:*¨¨* ❀ *¨¨*:·.</p>

#### disclaimer

nosycat is a checklist in script form. It reports common misconfigurations; it does not prove a server is secure, and a clean run is not an audit. Fix commands are generic suggestions: read them, adapt them to your setup, and keep a second SSH session open before touching SSH or firewall settings. Run it only on systems you own or are authorized to assess.

<p align="center">.·:*¨¨* ❀ *¨¨*:·.</p>

#### license

[MIT](LICENSE) © Ana Beatriz
