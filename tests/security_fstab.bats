#!/usr/bin/env bats
# SEC-006: fstab data and network mounts that can block boot.

load helpers

setup() {
  load_nosycat
  use_stubs
  # Skip unrelated privileged searches and use fixture mount options.
  IS_ROOT=0 VIRT_KIND=container CUR_MOD=security
  export NOSY_PROC_MOUNTS="$FIX/mounts/debian-shm.mounts"
}

fstab() { export NOSY_FSTAB="$FIX/fstab/$1"; nosy mod_security; }

@test "SEC-006: local data mounts without nofail WARN" {
  fstab local.fstab
  assert_status SEC-006 WARN
  [ "$(result_field SEC-006 TITLE)" = "data mounts without nofail: /data (ext4), /backup (xfs)" ]
}

@test "SEC-006: local data mounts with nofail are OK" {
  fstab nofail.fstab
  assert_status SEC-006 OK
  [ "$(result_field SEC-006 TITLE)" = "no fstab data mounts that can block boot" ]
}

@test "SEC-006: x-systemd.automount avoids the nofail warning" {
  fstab automount.fstab
  assert_status SEC-006 OK
}

@test "SEC-006: comments, system mounts, bind, noauto and tmpfs are ignored" {
  fstab ignored.fstab
  assert_status SEC-006 OK
}

@test "SEC-006: NFS without nofail or _netdev lists both warnings" {
  fstab network.fstab
  assert_status SEC-006 WARN
  [ "$(result_field SEC-006 TITLE)" = "data mounts without nofail: /mnt/nas (nfs); network mounts without _netdev: /mnt/nas" ]
}

@test "SEC-006: NFS with nofail but no _netdev has only the network warning" {
  fstab network-nofail.fstab
  assert_status SEC-006 WARN
  [ "$(result_field SEC-006 TITLE)" = "network mounts without _netdev: /mnt/nas" ]
}

@test "SEC-006: _netdev does not replace nofail for NFS" {
  fstab network-netdev.fstab
  assert_status SEC-006 WARN
  [ "$(result_field SEC-006 TITLE)" = "data mounts without nofail: /mnt/nas (nfs)" ]
}

@test "SEC-006: NFS with nofail and _netdev is OK" {
  fstab network-safe.fstab
  assert_status SEC-006 OK
}

@test "SEC-006: a missing fstab is SKIP" {
  export NOSY_FSTAB="$BATS_TEST_TMPDIR/missing-fstab"
  nosy mod_security
  assert_status SEC-006 SKIP
  [ "$(result_field SEC-006 TITLE)" = "fstab nofail" ]
  [ "$(result_field SEC-006 DETAIL)" = "/etc/fstab not readable" ]
}
