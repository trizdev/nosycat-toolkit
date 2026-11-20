# changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/).

## [0.2.2] - Unreleased

### fixed

- **UPD-001:** failed or timed-out pending update queries are a SKIP instead of "no pending updates" or a count from failed output. checkupdates exit 2 and an empty `pacman -Qu` exit 1 still mean no updates; dnf/yum already handled query errors. Zypper exit 106 with listed updates keeps the count, marked partial.

## [0.2.1] - 2026-11-18

### fixed

- **`.nosycat.ignore` and `#`:** a `#` inside a reason no longer cuts the line. Before, `BKP-001: see ticket #123 until 2026-11-01` lost its date and silently became a permanent ignore; now the reason keeps `#123` and the entry expires. `#` starts a comment only at the start of a line or right after the id.
- **`.nosycat.ignore` and `until`:** matched in any case (`Until`, `UNTIL`), so those entries no longer become permanent. A trailing `until` without a date is a warning on stderr and the entry is skipped, like an invalid date.
- **BKP-004:** repository paths are resolved with `stat -L`, so `/backup` as a symlink to a second volume is no longer "stored on the root filesystem". When `stat` cannot tell, the path is never counted as a separate filesystem (SKIP with "could not determine" when nothing else is known).
- **JSON:** bytes that are not valid UTF-8 (for example a SUID file named `/tmp/nosy\xffbad`) are replaced with `?`, so the report always parses as UTF-8. Before, any local user could make the JSON unreadable for Python-based consumers.
- **BKP-002:** a backup tool named only in a trailing cron comment (`sync.sh  # TODO: switch to restic`) is no longer a schedule; commented text is also ignored when looking for restic repository paths.
- **BKP-003:** timeshift snapshot names are read as local time (they were taken as UTC). The age is compared in seconds against `--backup-max-age`, so 7 days and 5 hours is over a 7-day limit (it used to pass as "7 days"); ages under a day are shown in hours.
- **BKP-003:** with borgmatic and no readable borg metadata, the SKIP now says why instead of ending in an empty "cannot tell without a password:".
- **Markdown:** `*`, `_`, `` ` ``, `[`, `]`, `<`, `>` and `\` in titles and details are escaped (only `|` was), and fixes stay intact code spans. With `--ascii` or a non-UTF-8 locale the report is plain ASCII.
- **CLI:** empty `--only=`, `--skip=`, `--format=`, `--output=`, `--state-dir=` and `--ignore=` are usage errors (exit 3) instead of being ignored. `--timeout` must be 1 or more (`timeout 0` meant no limit) and also accepts `--timeout=N`. `--list` prints only the modules `--only` / `--skip` accept (`snapshot` is the `--snapshot` / `--diff` mode, not a module).
- **SSH-006:** without root, when no sudo/wheel/admin member is found and the sudoers files cannot be read, it is a SKIP instead of a WARN. Sudoers are read from `$ETC` (fixtures), `%group ALL=... ALL` lines count the group's members, partial grants (`user ALL=(ALL) /usr/bin/systemctl`) and `User_Alias` names do not, and `root` in an admin group is no longer listed as a non-root admin.

### docs

- `docs/json.md`: `ignore_expired` is the entry's `until` date (the last day it applied), not the day it expired.
- README and `docs/checks.md`: comment rules and case-insensitive `until` in `.nosycat.ignore`; BKP-003 caveat that restic/borg metadata is also refreshed by read-only commands like `restic snapshots` or `borg list`.

## [0.2.0] - 2026-11-18

### added

- **`-q` / `--problems-only`:** only WARN/FAIL checks, with their why and fix, plus the summary. A module header is printed only when the module has something to show, the banner shrinks to one line and the not-root note to a short one. `--format md` keeps only the WARN/FAIL rows (with a note); `--format json` keeps only WARN/FAIL in `checks[]` and sets `"problems_only": true`. Summary counts and the exit code always cover every check.
- **Expiry for accepted findings:** `.nosycat.ignore` lines can end in `until YYYY-MM-DD` (`SEC-005: installer needs exec until 2027-01-31`, or `SEC-005 until 2027-01-31`). The entry applies through that day; afterwards the check shows its real status with `ignore expired DATE (reason)`, counts for the exit code, and the summary lists the expired ids. Permanent entries get a gentle tip in the summary to set a date. Invalid dates are a warning on stderr and the entry is skipped. JSON adds `ignore_until` (string or `null`) on IGNORED checks, `ignore_expired` on checks whose ignore ran out, and `summary.ignore_expired`.
- **`backup` module (BKP-001..004):** detects restic, borg/borgmatic, rsnapshot, timeshift, duplicity, duplicati and kopia; finds their schedule in cron (`/etc/crontab`, `cron.d`, `cron.*`, the spool; commented lines ignored), enabled systemd timers and timeshift's own config; reads the age of the last backup from metadata that needs no password (restic cache or local repo `snapshots/`, borg `security/*/manifest-timestamp`, rsnapshot `<interval>.0`, timeshift snapshot names, duplicity cache); and warns when the only copies are on the root filesystem. `--backup-max-age DAYS` (default 7). No tool is a WARN that reminds you provider snapshots are invisible from inside the VM; an age it cannot read is a SKIP with the reason. Never runs a backup tool or reads a password, env file or keyring.
- **JSON `schema_version`** (`"1"`), first field of the report, with a stability policy in [`docs/json.md`](docs/json.md): additive changes keep the version, removed/renamed fields, type changes and new `status` values bump it.
- `SECURITY.md` (supported versions, private reporting through GitHub Security Advisories, what counts as a vulnerability) and a "false positive" issue form asking for the check id, distro and redacted `--format json --only <module>` output.
- Fixture hooks `NOSY_FX_TODAY`, `NOSY_FX_NOW`, `NOSY_FS` and `NOSY_FX_BKP_TOOLS` for the new tests; CI also runs `-q` (text and JSON) in every container and checks `schema_version`.

### changed

- JSON reports now start with `schema_version` and include `problems_only` and `summary.ignore_expired` (additive; `schema_version` stays `"1"`).

## [0.1.1] - 2026-11-16

### fixed

- **NET-002 / firewall detection:** nftables and iptables count as a firewall only when a chain hooked on `input` filters (policy drop, or a drop/reject rule in that chain or a chain it jumps to). Before, any `drop` anywhere matched, so the `DOCKER-ISOLATION-*` chains on a Docker host made an unfiltered server look protected. A lone `ct state invalid drop` no longer counts either.
- **DKR-005:** published container ports are a FAIL with any active host firewall (ufw, firewalld, nftables, iptables), since Docker bypasses INPUT for all of them; without a firewall it stays a WARN next to the NET-002 FAIL.
- **DB-002:** Redis is probed on the host:port it actually listens on (private IPs and non-default ports included), and is OK only on a `NOAUTH` reply. Connection refused, timeouts and other replies are a SKIP with the reason; `DENIED` (protected mode, no password) is a WARN. A `REDISCLI_AUTH` in the caller's environment is ignored.
- **CLD-004:** compares with the effective `PasswordAuthentication` (`sshd -T`, or the parsed config with first-value-wins), so a `50-cloud-init.conf` "yes" overridden by an earlier "no" is OK.
- `addr_scope`: the whole `fe80::/10` link-local range (`fe8x`-`febx`) is private, and `fd::`-style addresses are no longer mistaken for ULA.
- `ssh_ports` collects every `Port` and `ListenAddress host:port`, so SSH on a second port is not reported as exposed in NET-001.
- Fix commands reload the right unit: `ssh` on Debian/Ubuntu, `sshd` on RHEL and others, `rc-service sshd` on OpenRC.
- `--diff` fails if `mktemp -d` fails instead of using a predictable `/tmp/nosycat.PID` path, and temp dirs are removed on exit, Ctrl-C and TERM.
- **SEC-004:** SUID binaries must be owned by a package (`dpkg -S`, `rpm -qf`, `apk info --who-owns`, `pacman -Qo`, merged-`/usr` aware). A SUID file named `sudo` in `/opt` is no longer "known". The name list is only a fallback when no ownership tool exists.
- **NET-002 / fail2ban and CrowdSec:** IP ban lists are not a firewall. Rules that only drop/reject listed sources (`ip saddr @set`, `saddr { ... }`, a single `saddr`; iptables `-s IP` and `-m set --match-set NAME src`) no longer count, and the `f2b-*` and `crowdsec*` nftables tables are ignored entirely, so a server with only fail2ban or CrowdSec is a FAIL/WARN instead of "firewall active". Allowlists (`saddr != @trusted drop`, `! -s NET -j DROP`) and a real firewall next to fail2ban are still detected; the NET-002 detail says when fail2ban or CrowdSec was seen.
- Titles, details and fix commands are trimmed, so SVC-001 no longer ends in a stray space (`failed units: casper-md5check.service `).
- **WEB-004:** only certificates used by the enabled config count (`nginx -T` as root, else `nginx.conf`, `conf.d`, `sites-enabled`; apache `sites-enabled`, `conf-enabled`, `conf.d`). Expired certs in `sites-available` no longer FAIL; unused Let's Encrypt lineages are a WARN.

### added

- `.nosycat.ignore` in the state dir and `--ignore FILE` (repeatable): accepted WARN/FAIL results become `IGNORED`, keep `original_status` and `ignore_reason` in JSON, and do not affect the exit code.
- Pretty text summary: a boxed card with FAIL/WARN/OK/SKIP counts and a proportional bar colored by status, status by module in two columns, a "fix first" list (FAIL before WARN, top 8, `+N more`), a verdict with a cat face (`=x.x=` failures, `=o.o=` warnings, `=^.^=` all clear) and how many of the skipped checks need root (`4 of 5 skipped checks need root`). Laid out by display width so it stays aligned and fits 80 columns. Same indentation as the check stream: headings (`❀ by module`, `❀ fix first`, the divider) at column 0, the box and every item at column 2.
- `INFO` status for notes about the run itself: counted in JSON (`summary.info`) and Markdown, never in "fix first" or the exit code.
- Single-file release asset: `nosycat.sh` with `lib/` and `modules/` inlined (`scripts/bundle.sh`, reproducible), published with its `.sha256` next to the tarball. CI checks that it runs on its own and gives the same JSON and text output as the source tree.
- Pastel palette in truecolor or 256 colors (8-color fallback), also on the per-check status tags, ids and fix commands. `--color auto|always|never`; `auto` colors only a terminal and honours `NO_COLOR` and `TERM=dumb`. `--no-color` is `--color never`.
- ASCII fallback for the box, bar, symbols and banner when the locale is not UTF-8, or with `--ascii`.
- bats test suite (105 tests) with fixtures under `tests/`, run in CI on the runner and in the Ubuntu, Debian, Rocky Linux and Alpine containers. `NOSY_ETC` and `NOSY_FX_*` generalize the old `NOSY_FSTAB` fixture hook.
- Release workflow: pushing a `v*` tag runs lint and tests, then publishes `nosycat-toolkit-X.Y.Z.tar.gz`, the single-file `nosycat.sh` and a `.sha256` for each. The README documents a verified install from a release.

### changed

- Less noise: a web server (nginx, apache, caddy, traefik, haproxy, lighttpd, envoy) on tcp 80/443 is expected in NET-001, and `/dev/shm` without `noexec` (Debian default) is noted in SEC-005's detail instead of raising a WARN.
- **ENV-006:** running without root is an `INFO` note (and the top-of-run note names the user) instead of a WARN, so it no longer leads "fix first" or turns the exit code into 1.
- The script banner is the README art (the cat typing `$ sniff`).
- README: CI status badge instead of the static ShellCheck badge. All GitHub Actions are pinned by commit SHA.

## [0.1.0] - 2026-11-16

### added

- `nosycat.sh` runner with `--only`, `--skip`, `--format text|md|json`, `--output`, `--no-color`, `--snapshot`, `--diff`, `--state-dir`, `--timeout`, `--list`, `--help`, `--version`.
- 11 check modules: environment, cloud_init, system, access, network, updates, docker, services, web_tls, security, databases (67 checks, see `docs/checks.md`).
- snapshot module: baseline of listeners, enabled units, users, admin groups, cron/timers, authorized_keys hashes, package count and containers, with `--diff` against it.
- Exit codes: 0 all OK, 1 WARN present, 2 FAIL present, 3 usage/runtime error.
- Support for Debian/Ubuntu, RHEL/Rocky/Alma, Alpine and Arch (apt, dnf/yum, apk, pacman, zypper; ufw, firewalld, nftables, iptables).
- Per-command timeouts so no check can hang the run.
- CI: `bash -n`, ShellCheck and test runs in Ubuntu, Debian, Rocky Linux and Alpine containers.
