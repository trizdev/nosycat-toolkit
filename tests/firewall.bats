#!/usr/bin/env bats
# Bug 1: the nftables check must only look at chains hooked on input.

load helpers

setup() { load_nosycat; }

fw() { export NOSY_FX_NFT="$FIX/nft/$1"; nosy detect_firewall; }

@test "docker on iptables-nft with INPUT policy accept is NOT a firewall" {
  fw docker-no-filter.nft
  [ "$FW_ACTIVE" = "none" ]
}

@test "input chain with policy drop is a firewall" {
  fw input-policy-drop.nft
  [ "$FW_ACTIVE" = "nftables" ]
}

@test "input chain with policy accept and a final drop rule is a firewall" {
  fw input-drop-rule.nft
  [ "$FW_ACTIVE" = "nftables" ]
}

@test "input chain that only drops invalid conntrack state is not a firewall" {
  fw input-only-invalid-drop.nft
  [ "$FW_ACTIVE" = "none" ]
}

@test "input chain that jumps to a chain with reject is a firewall" {
  fw input-jump.nft
  [ "$FW_ACTIVE" = "nftables" ]
}

@test "firewalld-style nft ruleset (reject at the end of filter_INPUT) is a firewall" {
  fw firewalld.nft
  [ "$FW_ACTIVE" = "nftables" ]
}

@test "iptables INPUT policy DROP is a firewall" {
  export NOSY_FX_IPTABLES_INPUT="$FIX/iptables/input-drop.rules"
  nosy detect_firewall
  [ "$FW_ACTIVE" = "iptables" ]
}

@test "iptables INPUT accept with only an INVALID drop is not a firewall" {
  export NOSY_FX_IPTABLES_INPUT="$FIX/iptables/input-accept-invalid.rules"
  nosy detect_firewall
  [ "$FW_ACTIVE" = "none" ]
}

@test "ufw status fixture wins first" {
  printf 'Status: active\n' >"$BATS_TEST_TMPDIR/ufw"
  export NOSY_FX_UFW_STATUS="$BATS_TEST_TMPDIR/ufw" NOSY_FX_NFT="$FIX/nft/input-policy-drop.nft"
  nosy detect_firewall
  [ "$FW_ACTIVE" = "ufw" ]
}

@test "non-root cannot read rules: firewall is unknown" {
  IS_ROOT=0
  fw input-policy-drop.nft
  [ "$FW_ACTIVE" = "unknown" ]
}

@test "NET-002 FAILs on a docker host whose only drops are in DOCKER-ISOLATION" {
  fake_etc
  export NOSY_FX_SS="$FIX/ss/docker-host.ss" NOSY_FX_SSHD_T="$FIX/sshd/pa-no.sshd-T"
  fw docker-no-filter.nft
  nosy mod_network
  assert_status NET-002 FAIL
  assert_status NET-001 WARN
}

@test "DKR-005 FAILs when a real nftables firewall is bypassed by published ports" {
  use_stubs
  printf '/web|false|unless-stopped|json-file|10m||0.0.0.0:3000>3000/tcp,\n' >"$BATS_TEST_TMPDIR/inspect"
  export DOCKER_STUB_INSPECT="$BATS_TEST_TMPDIR/inspect"
  fw input-policy-drop.nft
  nosy mod_docker
  assert_status DKR-005 FAIL
}

@test "DKR-005 stays WARN (NET-002 carries the FAIL) when there is no firewall at all" {
  use_stubs
  printf '/web|false|unless-stopped|json-file|10m||0.0.0.0:3000>3000/tcp,\n' >"$BATS_TEST_TMPDIR/inspect"
  export DOCKER_STUB_INSPECT="$BATS_TEST_TMPDIR/inspect"
  fw docker-no-filter.nft
  nosy mod_docker
  assert_status DKR-005 WARN
}

# Review 2: fail2ban / CrowdSec ban lists hooked on input are not a firewall.

@test "fail2ban-only nft (inet f2b-table, saddr @set reject) is NOT a firewall" {
  fw fail2ban-only.nft
  [ "$FW_ACTIVE" = "none" ]
  [ "$FW_BANNERS" = "fail2ban" ]
}

@test "crowdsec-only nft (ip crowdsec + ip6 crowdsec6, saddr @set drop) is NOT a firewall" {
  fw crowdsec-only.nft
  [ "$FW_ACTIVE" = "none" ]
  [ "$FW_BANNERS" = "crowdsec" ]
}

@test "a real inet filter with policy drop next to fail2ban is still a firewall" {
  fw fail2ban-plus-filter.nft
  [ "$FW_ACTIVE" = "nftables" ]
}

@test "input chain whose drops only match source addresses (set, anonymous set, single IP) is NOT a firewall" {
  fw custom-blocklist-only.nft
  [ "$FW_ACTIVE" = "none" ]
  [ "$FW_BANNERS" = "" ]
}

@test "saddr != @trusted drop is an allowlist, so it IS a firewall" {
  fw allowlist-saddr.nft
  [ "$FW_ACTIVE" = "nftables" ]
}

@test "iptables with only fail2ban (f2b chain jump, ipset REJECT, single-IP REJECT) is NOT a firewall" {
  export NOSY_FX_IPTABLES_INPUT="$FIX/iptables/fail2ban-only.rules"
  nosy detect_firewall
  [ "$FW_ACTIVE" = "none" ]
  [ "$FW_BANNERS" = "fail2ban" ]
}

@test "iptables with only the crowdsec ipset DROP is NOT a firewall" {
  export NOSY_FX_IPTABLES_INPUT="$FIX/iptables/crowdsec-only.rules"
  nosy detect_firewall
  [ "$FW_ACTIVE" = "none" ]
  [ "$FW_BANNERS" = "crowdsec" ]
}

@test "iptables policy DROP next to fail2ban is still a firewall" {
  export NOSY_FX_IPTABLES_INPUT="$FIX/iptables/fail2ban-plus-drop.rules"
  nosy detect_firewall
  [ "$FW_ACTIVE" = "iptables" ]
}

@test "iptables '! -s NET -j DROP' is an allowlist, so it IS a firewall" {
  export NOSY_FX_IPTABLES_INPUT="$FIX/iptables/allowlist-not-src.rules"
  nosy detect_firewall
  [ "$FW_ACTIVE" = "iptables" ]
}

@test "ip6tables: a crowdsec6 ipset DROP alone does not filter" {
  ! printf '%s\n' '-P INPUT ACCEPT' '-A INPUT -m set --match-set crowdsec6-blacklists src -j DROP' | iptables_input_filters
}

@test "NET-002 FAILs on a fail2ban-only server and says fail2ban is not a firewall" {
  fake_etc
  export NOSY_FX_SS="$FIX/ss/docker-host.ss" NOSY_FX_SSHD_T="$FIX/sshd/pa-no.sshd-T"
  fw fail2ban-only.nft
  nosy mod_network
  assert_status NET-002 FAIL
  [[ "$(result_field NET-002 DETAIL)" == *"fail2ban only bans listed IPs; it is not a firewall"* ]]
}

# NET-003 must check IPv6 input filtering even when IPv4 is already filtered.
ipv6_fw() {
  fake_etc
  export NOSY_FX_SS=/dev/null NOSY_FX_SSHD_T="$FIX/sshd/pa-no.sshd-T"
  export NOSY_PROC_IF_INET6="$BATS_TEST_TMPDIR/if_inet6"
  printf '20010db8000000000000000000000001 02 40 00 80 eth0\n' >"$NOSY_PROC_IF_INET6"
  export NOSY_FX_NFT="$BATS_TEST_TMPDIR/ruleset.nft"
  sed 's/^table inet /table ip /' "$FIX/nft/input-policy-drop.nft" >"$NOSY_FX_NFT"
  cat "$1" >>"$NOSY_FX_NFT"
  nosy detect_firewall
  [ "$FW_ACTIVE" = "nftables" ]
  nosy mod_network
}

@test "NET-003 WARNs with only an IPv4 input filter" {
  ipv6_fw /dev/null
  assert_status NET-003 WARN
}

@test "NET-003 WARNs with an IPv4 filter and an empty inet table" {
  printf 'table inet empty {\n}\n' >"$BATS_TEST_TMPDIR/empty.nft"
  ipv6_fw "$BATS_TEST_TMPDIR/empty.nft"
  assert_status NET-003 WARN
}

@test "NET-003 WARNs with an IPv4 filter and only fail2ban in inet" {
  ipv6_fw "$FIX/nft/fail2ban-only.nft"
  assert_status NET-003 WARN
}

@test "NET-003 WARNs with an IPv4 filter and only CrowdSec in ip6" {
  ipv6_fw "$FIX/nft/crowdsec-only.nft"
  assert_status NET-003 WARN
}

@test "NET-003 WARNs when inet only filters forward, not input" {
  sed 's/hook input/hook forward/' "$FIX/nft/input-policy-drop.nft" >"$BATS_TEST_TMPDIR/forward.nft"
  ipv6_fw "$BATS_TEST_TMPDIR/forward.nft"
  assert_status NET-003 WARN
}

@test "NET-003 WARNs when inet input only drops invalid conntrack state" {
  ipv6_fw "$FIX/nft/input-only-invalid-drop.nft"
  assert_status NET-003 WARN
}

@test "NET-003 WARNs when inet input only drops listed sources" {
  ipv6_fw "$FIX/nft/custom-blocklist-only.nft"
  assert_status NET-003 WARN
}

@test "NET-003 is OK with an inet input policy drop next to fail2ban" {
  ipv6_fw "$FIX/nft/fail2ban-plus-filter.nft"
  assert_status NET-003 OK
  [[ "$(result_field NET-003 TITLE)" == *"IPv6 covered by nftables"* ]]
}

@test "NET-003 is OK with an ip6 input policy drop" {
  sed 's/^table inet /table ip6 /' "$FIX/nft/input-policy-drop.nft" >"$BATS_TEST_TMPDIR/ip6.nft"
  ipv6_fw "$BATS_TEST_TMPDIR/ip6.nft"
  assert_status NET-003 OK
  [[ "$(result_field NET-003 TITLE)" == *"IPv6 covered by nftables"* ]]
}

@test "NET-003 is OK when inet input jumps to a rejecting chain" {
  ipv6_fw "$FIX/nft/input-jump.nft"
  assert_status NET-003 OK
  [[ "$(result_field NET-003 TITLE)" == *"IPv6 covered by nftables"* ]]
}

@test "NET-003 counts an IPv6 source allowlist" {
  sed 's/ipv4_addr/ipv6_addr/; s/192\.0\.2\.10/2001:db8::10/; s/ip saddr/ip6 saddr/' "$FIX/nft/allowlist-saddr.nft" >"$BATS_TEST_TMPDIR/allowlist.nft"
  ipv6_fw "$BATS_TEST_TMPDIR/allowlist.nft"
  assert_status NET-003 OK
  [[ "$(result_field NET-003 TITLE)" == *"IPv6 covered by nftables"* ]]
}

@test "NET-003 is OK with only a link-local IPv6 address" {
  fake_etc
  export NOSY_FX_SS=/dev/null NOSY_FX_SSHD_T="$FIX/sshd/pa-no.sshd-T"
  export NOSY_PROC_IF_INET6="$BATS_TEST_TMPDIR/if_inet6"
  printf 'fe800000000000000000000000000001 02 40 20 80 eth0\n' >"$NOSY_PROC_IF_INET6"
  nosy mod_network
  assert_status NET-003 OK
  [ "$(result_field NET-003 TITLE)" = "no global IPv6 address" ]
}
