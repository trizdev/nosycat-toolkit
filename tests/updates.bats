#!/usr/bin/env bats
# UPD-001 must not count a failed query as an empty list of updates.

load helpers

setup() {
  load_nosycat
  set -o pipefail
  VIRT_KIND=container
  QUERY_RC=0 QUERY_REPLY="" CHECKUPDATES=1
  # Keep the package queries and unrelated update checks off the host.
  t() {
    shift
    case "$*" in
      *updateinfo*|*' lp '*) return 0 ;;
    esac
    printf '%s\n' "$QUERY_REPLY"
    return "$QUERY_RC"
  }
  dpkg-query() { return 1; }
  unit_enabled() { return 1; }
  have() { [ "$1" = checkupdates ] && [ "$CHECKUPDATES" -eq 1 ]; }
}

assert_query_skip() {
  nosy mod_updates
  assert_status UPD-001 SKIP
  [ "$(result_field UPD-001 TITLE)" = "pending updates" ]
  [ "$(result_field UPD-001 DETAIL)" = "no supported package manager or query timed out" ]
  [ "$(result_field UPD-001 FIX)" = "" ]
}

@test "apt query error is SKIP, not no pending updates" {
  PKG_MGR=apt-get QUERY_RC=100
  assert_query_skip
}

@test "apt query timeout is SKIP" {
  PKG_MGR=apt-get QUERY_RC=124
  assert_query_skip
}

@test "apk query error is SKIP, not no pending updates" {
  PKG_MGR=apk QUERY_RC=1
  assert_query_skip
}

@test "apk query timeout is SKIP" {
  PKG_MGR=apk QUERY_RC=124
  assert_query_skip
}

@test "apk query busybox timeout is SKIP" {
  PKG_MGR=apk QUERY_RC=143
  assert_query_skip
}

@test "checkupdates query error is SKIP" {
  PKG_MGR=pacman QUERY_RC=1
  assert_query_skip
}

@test "checkupdates query timeout is SKIP" {
  PKG_MGR=pacman QUERY_RC=124
  assert_query_skip
}

@test "pacman query timeout is SKIP" {
  PKG_MGR=pacman CHECKUPDATES=0 QUERY_RC=124
  assert_query_skip
}

@test "pacman -Qu exit 1 with output is SKIP" {
  PKG_MGR=pacman CHECKUPDATES=0 QUERY_RC=1 QUERY_REPLY='curl 1.0 -> 1.1'
  assert_query_skip
}

@test "zypper query error is SKIP" {
  PKG_MGR=zypper QUERY_RC=7
  assert_query_skip
}

@test "zypper query timeout is SKIP" {
  PKG_MGR=zypper QUERY_RC=124
  assert_query_skip
}

@test "zypper exit 106 with a listed update is a partial WARN" {
  PKG_MGR=zypper QUERY_RC=106 QUERY_REPLY='v | repo | curl | 1.1'
  nosy mod_updates
  assert_status UPD-001 WARN
  [ "$(result_field UPD-001 TITLE)" = "1 pending update(s) (partial: a repository was skipped)" ]
}

@test "zypper exit 106 with nothing listed is SKIP" {
  PKG_MGR=zypper QUERY_RC=106 QUERY_REPLY='Repository metadata could not be loaded.'
  assert_query_skip
}

@test "partial output from a failed query is not a pending update count" {
  QUERY_RC=124
  QUERY_REPLY=$'Inst openssl [1.0] (1.1 Debian-Security [amd64])\nInstalled: Available:\nopenssl-1.0 < 1.1\nv | repo | openssl | 1.1'
  for PKG_MGR in apt-get apk pacman zypper; do
    assert_query_skip
  done
}

@test "successful empty queries still report no pending updates" {
  for PKG_MGR in apt-get apk pacman zypper dnf yum; do
    nosy mod_updates
    assert_status UPD-001 OK
    [[ "$(result_field UPD-001 TITLE)" == "no pending updates"* ]]
  done
}

@test "successful queries still count pending updates" {
  for PKG_MGR in apt-get apk pacman zypper; do
    case "$PKG_MGR" in
      apt-get) QUERY_REPLY='Inst curl [1.0] (1.1 Debian [amd64])' ;;
      apk) QUERY_REPLY=$'Installed: Available:\ncurl-1.0 < 1.1' ;;
      pacman) QUERY_REPLY='curl 1.0 -> 1.1' ;;
      zypper) QUERY_REPLY='v | repo | curl | 1.1' ;;
    esac
    nosy mod_updates
    assert_status UPD-001 WARN
    if [ "$PKG_MGR" = zypper ]; then
      [ "$(result_field UPD-001 TITLE)" = "1 pending update(s)" ]
    else
      [[ "$(result_field UPD-001 TITLE)" == "1 pending update(s)"* ]]
    fi
  done
}

@test "apt security updates still report FAIL" {
  PKG_MGR=apt-get
  QUERY_REPLY='Inst openssl [1.0] (1.1 Debian-Security [amd64])'
  nosy mod_updates
  assert_status UPD-001 FAIL
  [[ "$(result_field UPD-001 TITLE)" == "1 pending update(s), 1 security"* ]]
}

@test "checkupdates exit 2 still means no pending updates" {
  PKG_MGR=pacman QUERY_RC=2
  nosy mod_updates
  assert_status UPD-001 OK
}

@test "pacman -Qu exit 1 with no output still means no pending updates" {
  PKG_MGR=pacman CHECKUPDATES=0 QUERY_RC=1
  nosy mod_updates
  assert_status UPD-001 OK
}

@test "dnf and yum keep their query error, timeout and updates exit codes" {
  for PKG_MGR in dnf yum; do
    QUERY_RC=1
    assert_query_skip
    QUERY_RC=124
    assert_query_skip
    QUERY_RC=100 QUERY_REPLY='curl.x86_64 1.1 updates'
    nosy mod_updates
    assert_status UPD-001 WARN
    [[ "$(result_field UPD-001 TITLE)" == "1 pending update(s)"* ]]
    QUERY_REPLY=""
  done
}
