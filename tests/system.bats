#!/usr/bin/env bats
# Disk, inode and OOM checks must distinguish missing data from a clean result.

load helpers

setup() {
  load_nosycat
  use_stubs
  CUR_MOD=system
  systemd_up() { return 0; }
  export DF_STUB_DISK DF_STUB_INODES
  DF_STUB_DISK="$(df_reply 0)"; DF_STUB_INODES="$(df_reply 0)"
  export DF_STUB_RC=0 JOURNALCTL_STUB_RC=0 DMESG_STUB_RC=0
  export JOURNALCTL_STUB_REPLY="kernel: boot complete" DMESG_STUB_REPLY="kernel: boot complete"
  export JOURNALCTL_STUB_PROBE_REPLY="kernel: boot complete" JOURNALCTL_STUB_PROBE_RC=0
}

df_reply() {
  printf 'Filesystem Blocks Used Available Capacity Mounted on\n/dev/vda1 100 0 100 %s%% /\n' "$1"
}

@test "SYS-007: empty df output is SKIP even when inode usage is readable" {
  export DF_STUB_DISK=""
  nosy mod_system
  assert_status SYS-007 SKIP
  [ "$(result_field SYS-007 DETAIL)" = "not readable" ]
  assert_status SYS-008 OK
}

@test "SYS-008: empty df -Pi output is SKIP even when disk usage is readable" {
  export DF_STUB_INODES=""
  nosy mod_system
  assert_status SYS-008 SKIP
  [ "$(result_field SYS-008 DETAIL)" = "not readable" ]
  assert_status SYS-007 OK
}

@test "SYS-007/008: failed df with no output is SKIP" {
  export DF_STUB_DISK="" DF_STUB_INODES="" DF_STUB_RC=1
  nosy mod_system
  assert_status SYS-007 SKIP
  assert_status SYS-008 SKIP
}

@test "SYS-007/008: df with only a header is SKIP" {
  export DF_STUB_DISK="Filesystem Blocks Used Available Capacity Mounted on"
  export DF_STUB_INODES="$DF_STUB_DISK"
  nosy mod_system
  assert_status SYS-007 SKIP
  assert_status SYS-008 SKIP
}

@test "SYS-007/008: df without numeric percentages is SKIP" {
  export DF_STUB_DISK DF_STUB_INODES
  DF_STUB_DISK="$(df_reply -)"; DF_STUB_INODES="$(df_reply -)"
  nosy mod_system
  assert_status SYS-007 SKIP
  assert_status SYS-008 SKIP
}

@test "SYS-007/008: a real 0% reading is still OK" {
  nosy mod_system
  assert_status SYS-007 OK
  assert_status SYS-008 OK
  [ "$(result_field SYS-007 TITLE)" = "disk usage below 80% (max 0%)" ]
  [ "$(result_field SYS-008 TITLE)" = "inode usage below 80% (max 0%)" ]
}

@test "SYS-007/008: usage at 80% is WARN" {
  export DF_STUB_DISK DF_STUB_INODES
  DF_STUB_DISK="$(df_reply 80)"; DF_STUB_INODES="$(df_reply 80)"
  nosy mod_system
  assert_status SYS-007 WARN
  assert_status SYS-008 WARN
  [ "$(result_field SYS-007 TITLE)" = "disk usage high: / 80%" ]
  [ "$(result_field SYS-008 TITLE)" = "inode usage high: / 80%" ]
}

@test "SYS-007/008: a full filesystem is FAIL even when the last row is 0%" {
  export DF_STUB_DISK DF_STUB_INODES
  DF_STUB_DISK="$(df_reply 90; printf '/dev/vdb1 100 0 100 0%% /data\n')"
  DF_STUB_INODES="$DF_STUB_DISK"
  nosy mod_system
  assert_status SYS-007 FAIL
  assert_status SYS-008 FAIL
  [ "$(result_field SYS-007 TITLE)" = "disk almost full: / 90%" ]
  [ "$(result_field SYS-008 TITLE)" = "inodes almost exhausted: / 90%" ]
}

@test "SYS-007/008: failed df with a valid 85% reading is WARN" {
  export DF_STUB_DISK DF_STUB_INODES DF_STUB_RC=1
  DF_STUB_DISK="$(df_reply 85)"; DF_STUB_INODES="$(df_reply 85)"
  nosy mod_system
  assert_status SYS-007 WARN
  assert_status SYS-008 WARN
  [ "$(result_field SYS-007 TITLE)" = "disk usage high: / 85%" ]
  [ "$(result_field SYS-008 TITLE)" = "inode usage high: / 85%" ]
}

@test "SYS-010: empty journal probe is SKIP" {
  export JOURNALCTL_STUB_PROBE_REPLY=""
  nosy mod_system
  assert_status SYS-010 SKIP
  [ "$(result_field SYS-010 DETAIL)" = "kernel log not readable (needs root/journal)" ]
}

@test "SYS-010: failed journal read with no output is SKIP" {
  export JOURNALCTL_STUB_REPLY="" JOURNALCTL_STUB_RC=1
  nosy mod_system
  assert_status SYS-010 SKIP
}

@test "SYS-010: failed journal read with partial output is SKIP" {
  export JOURNALCTL_STUB_RC=1
  nosy mod_system
  assert_status SYS-010 SKIP
}

@test "SYS-010: readable journal without OOM events is OK" {
  nosy mod_system
  assert_status SYS-010 OK
  [ "$(result_field SYS-010 TITLE)" = "no OOM kills in the last 7 days" ]
}

@test "SYS-010: readable kernel log with nothing in the last 7 days is OK" {
  export JOURNALCTL_STUB_REPLY=""
  nosy mod_system
  assert_status SYS-010 OK
  [ "$(result_field SYS-010 TITLE)" = "no OOM kills in the last 7 days" ]
}

@test "SYS-010: failed journal read with an OOM line is WARN" {
  export JOURNALCTL_STUB_RC=124 JOURNALCTL_STUB_REPLY="kernel: Killed process 123 (worker)"
  nosy mod_system
  assert_status SYS-010 WARN
  [ "$(result_field SYS-010 TITLE)" = "1 OOM-killer event(s) in the kernel log (7d)" ]
}

@test "SYS-010: OOM events in a readable journal are counted" {
  export JOURNALCTL_STUB_REPLY=$'kernel: Out of memory\nkernel: oom-kill\nkernel: Killed process 123 (worker)'
  nosy mod_system
  assert_status SYS-010 WARN
  [ "$(result_field SYS-010 TITLE)" = "3 OOM-killer event(s) in the kernel log (7d)" ]
}

@test "SYS-010: empty dmesg output is SKIP" {
  systemd_up() { return 1; }
  export DMESG_STUB_REPLY=""
  nosy mod_system
  assert_status SYS-010 SKIP
  [ "$(result_field SYS-010 DETAIL)" = "kernel log not readable (needs root/journal)" ]
}

@test "SYS-010: failed dmesg read with no output is SKIP" {
  systemd_up() { return 1; }
  export DMESG_STUB_REPLY="" DMESG_STUB_RC=1
  nosy mod_system
  assert_status SYS-010 SKIP
}

@test "SYS-010: failed dmesg read with partial output is SKIP" {
  systemd_up() { return 1; }
  export DMESG_STUB_RC=1
  nosy mod_system
  assert_status SYS-010 SKIP
}

@test "SYS-010: readable dmesg without OOM events is OK" {
  systemd_up() { return 1; }
  nosy mod_system
  assert_status SYS-010 OK
}

@test "SYS-010: failed dmesg read with an OOM line is WARN" {
  systemd_up() { return 1; }
  export DMESG_STUB_RC=1 DMESG_STUB_REPLY="kernel: Killed process 123 (worker)"
  nosy mod_system
  assert_status SYS-010 WARN
  [ "$(result_field SYS-010 TITLE)" = "1 OOM-killer event(s) in the kernel log (7d)" ]
}

@test "SYS-010: OOM events in readable dmesg are counted" {
  systemd_up() { return 1; }
  export DMESG_STUB_REPLY="kernel: Killed process 123 (worker)"
  nosy mod_system
  assert_status SYS-010 WARN
  [ "$(result_field SYS-010 TITLE)" = "1 OOM-killer event(s) in the kernel log (7d)" ]
}

@test "SYS-010: non-root without a journal still skips the kernel log" {
  systemd_up() { return 1; }
  IS_ROOT=0
  nosy mod_system
  assert_status SYS-010 SKIP
}
