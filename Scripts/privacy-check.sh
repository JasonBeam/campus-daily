#!/bin/sh
# The privacy checks to run before every commit. They read the staged
# content (the Git index), not the working tree, and print counts and
# file:line locations only, never the values themselves.
#
#   1. Pattern scan: identifier-shaped values (phone numbers, student ids,
#      meter addresses, long ids, MACs, machine ids, custid ciphertexts, card
#      record vouchers) in every tracked text file except images and Vendor/.
#   2. Value scan: every line of your private value list (your own real
#      student id, phone, room, device ids, tokens, platform secret...) must
#      not appear in any tracked file, ignoring case.
#   3. Marker scan: lines matching any extended regex in MARKER_PATTERNS
#      (one per line), except the path:line locations listed in MARKER_ALLOW.
#      Both files live outside Git, like the value list.
#
# Allowlists match the complete value, never a prefix or the rest of the
# line. Synthetic values in fixtures are therefore written in shapes no real
# id has: zero-padded counters (000...0991), a leading 99, or one of the few
# exact placeholders listed below.
#
# The value list lives outside Git. Its path comes from LEAKCHECK_FILE
# (default: private/capture/secrets/leakcheck.txt in the checkout). A missing
# list is a failure, and so is an unset MARKER_PATTERNS; pass --allow-missing
# to skip what is missing (reported as skipped).
#
#   LEAKCHECK_FILE=/path/to/leakcheck.txt MARKER_PATTERNS=/path/to/patterns.txt \
#   MARKER_ALLOW=/path/to/allow.txt sh Scripts/privacy-check.sh [--allow-missing] [repo]
#
# Exit 0: clean. Exit 1: something found. Exit 2: the check could not run
# (not a repo, git grep failed, nothing to scan, empty value list...), which
# must never be read as clean.
export LC_ALL=C
allow_missing=0
if [ "$1" = "--allow-missing" ]; then allow_missing=1; shift; fi
if [ -n "$1" ]; then
  cd "$1" || exit 2
fi
root=$(git rev-parse --show-toplevel) || exit 2
cd "$root" || exit 2
list=${LEAKCHECK_FILE:-$root/private/capture/secrets/leakcheck.txt}
hits=0
tmp=$(mktemp -d) || { echo "privacy-check: mktemp failed" >&2; exit 2; }
[ -n "$tmp" ] && [ -d "$tmp" ] || { echo "privacy-check: no temp dir" >&2; exit 2; }
trap 'rm -rf "$tmp"' EXIT
tab=$(printf '\t')

# git grep exits 0 on matches and 1 on none; anything else is an error and
# must stop the check instead of looking like "nothing found".
gitgrep() { # out-file git-grep-args...
  out=$1; shift
  git grep "$@" > "$out"; rc=$?
  if [ "$rc" -gt 1 ]; then echo "privacy-check: git grep failed ($rc)" >&2; exit 2; fi
}
# Staged text files, minus images and vendored binaries. -z separates path,
# line number and match with NUL so a ':' in a path can never shift the
# match into the location column; the result is "path:line<TAB>value".
scan() { # out-file extended-regex [-i]
  gitgrep "$tmp/raw" --cached -z -I -n -o $3 -E "$2" -- . ':(exclude)Vendor' \
    ':(exclude)*.png' ':(exclude)*.jpg' ':(exclude)*.jpeg' ':(exclude)*.webp'
  tr '\0' '\t' < "$tmp/raw" | awk -F'\t' 'NF >= 3 {
    v = $3; for (i = 4; i <= NF; i++) v = v "\t" $i
    print $1 ":" $2 "\t" v }' > "$1"
}
# Keep only lines whose value (after the TAB) is NOT a whole-value match of
# the allowlist. Anchored at both ends: "<TAB>(...)$".
notallowed() { # extended-regex [-i]
  grep -v $2 -E "${tab}($1)\$"
}
# Locations only: cut -s drops any line without a TAB instead of printing it.
report() { # label file-with-"loc<TAB>value"-lines
  n=$(grep -c . "$2")
  if [ "$n" -gt 0 ]; then
    echo "$1: $n"; cut -s -f1 "$2" | sort -u | head -20
    hits=$((hits+n))
  fi
}

# 0. Something must actually be scanned.
gitgrep "$tmp/files" --cached -I -l -e . -- . ':(exclude)Vendor' \
  ':(exclude)*.png' ':(exclude)*.jpg' ':(exclude)*.jpeg' ':(exclude)*.webp'
files=$(grep -c . "$tmp/files")
if [ "$files" -eq 0 ]; then
  echo "privacy-check: no staged text files to scan in $root" >&2; exit 2
fi

# 1. Pattern scan. Digit rules look at whole digit runs.
counter='0+[0-9]{1,3}'   # zero-padded counter: 000000000991, 0000...0002
scan "$tmp/digits" '[0-9]{11,}'
# CN mobile, 11 digits (13800000000 is the one synthetic number)
grep -E "${tab}1[3-9][0-9]{9}\$" "$tmp/digits" | notallowed '13800000000' > "$tmp/phone"
report "phone-like" "$tmp/phone"
# Mobile with the 86 country code, 13 digits
grep -E "${tab}861[3-9][0-9]{9}\$" "$tmp/digits" | notallowed '8613800000000' > "$tmp/phone86"
report "phone-like (86)" "$tmp/phone86"
# 0-prefixed 11 or 13 digits (student / user id shapes seen in real captures)
grep -E "${tab}0([0-9]{10}|[0-9]{12})\$" "$tmp/digits" | notallowed "$counter" > "$tmp/zeroid"
report "0-prefixed 11/13 digits" "$tmp/zeroid"
# 12 digits (electric meter comAddress) and 14 digits; 112233445566 is the
# placeholder MAC. 13-digit runs that are neither 0- nor 86-prefixed are
# millisecond timestamps and are left alone.
grep -E "${tab}([0-9]{12}|[0-9]{14})\$" "$tmp/digits" \
  | notallowed "$counter|99[0-9]*|10000000000[01]|00010203040506|112233445566" > "$tmp/meter"
report "12/14 digits" "$tmp/meter"
# 15+ digit ids (order numbers, card ids, area/room ids...). Besides the
# counters and 99-prefixed values: Xcode object ids (00XX + 16 zeros), the
# byte ramps used by the BLE golden tests, and the placeholder Alipay app_id.
grep -E "${tab}[0-9]{15,}\$" "$tmp/digits" \
  | notallowed "$counter|99[0-9]*|00[0-9]{2}0{16}|000102030405060708090|5511223344000102030405060708090|2000000000000000" > "$tmp/longid"
report "long numeric id" "$tmp/longid"
# MAC addresses with ':' or '-' separators
scan "$tmp/mac" '([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}'
notallowed '02([:-]00){4}[:-][0-9a-f]{2}|aa([:-])bb[:-]cc[:-]dd[:-]ee[:-]ff|11([:-])22[:-]33[:-]44[:-]55[:-]66' -i \
  < "$tmp/mac" > "$tmp/mac2"
report "MAC" "$tmp/mac2"
# MAC written as 12 hex digits in one run (all-digit runs are covered above).
# Allowed: the Bluetooth base UUID tail, the GATT service/characteristic
# placeholders, and the placeholder MACs.
scan "$tmp/hex12raw" '(^|[^0-9A-Za-z])[0-9A-Fa-f]{12}([^0-9A-Za-z]|$)'
sed "s/${tab}[^0-9A-Fa-f]*\([0-9A-Fa-f]*\).*/${tab}\1/" "$tmp/hex12raw" \
  | grep -E "${tab}[0-9]*[A-Fa-f]" \
  | notallowed '00805F9B34FB|FFE0FFE1FFE2|9A0B1C2D3E4F|AABBCCDDEEFF|112233445566' -i > "$tmp/hex12"
report "MAC (12 hex)" "$tmp/hex12"
# 8-hex machine ids next to a machineId / machine_id key in any shape
scan "$tmp/midraw" 'machine_?id[A-Za-z0-9_]*(\\?["'"'"']|%22|%3[AaDd]|[[:space:]:=,]|value)+[0-9A-Fa-f]{8}' -i
sed "s/${tab}.*\([0-9A-Fa-f]\{8\}\)\$/${tab}\1/" "$tmp/midraw" \
  | notallowed '11223344|1a2b3c4d|aabbccdd|99999999|0000000[0-9]' -i > "$tmp/mid"
report "machine id" "$tmp/mid"
# custid / syscustid ciphertexts in any key/value shape: JSON ("custid": "x"),
# JSON escaped inside a JSON string (\"custid\":\"x\"), URL-encoded
# (custid%22%3A%22x, custid%3Dx), query/plist/code (custid=x, custid: "x"),
# URLQueryItem(name: "custid", value: "x"), and suffixed keys (custidList).
# The value must be one of the synthetic shapes in full; a TEST prefix in
# front of anything else is not enough.
scan "$tmp/custraw" 'custid[A-Za-z0-9_]*(\\?["'"'"']|%22|%3[AaDd]|[[:space:]:=,]|value)+[A-Za-z0-9+/_-][A-Za-z0-9+/=_%-]{15,}' -i
sed -E "s/${tab}[^${tab}]*[Cc][Uu][Ss][Tt][Ii][Dd][A-Za-z0-9_]*(\\\\?[\"']|%22|%3[AaDd]|[[:space:]:=,]|[Vv][Aa][Ll][Uu][Ee])+/${tab}/" "$tmp/custraw" \
  | notallowed 'TESTid0+[0-9]{1,3}|TESTsyscus%(25)?3Ntid0+%(25)?1H00%(25)?7J|TESTcustid0+%(25)?1A00000%(25)?3G|mintedTokenAsInput|afterLoginBySysId' > "$tmp/custid"
report "custid ciphertext" "$tmp/custid"
# Card record vouchers (voucherno) next to a voucher key in any shape, as for
# custid. Only the synthetic shape is allowed: 99 and a zero-padded counter.
# A 99-prefixed long id passes the rule above; a voucher must be this exact shape.
scan "$tmp/vouchraw" 'voucher[A-Za-z0-9_]*(\\?["'"'"']|%22|%3[AaDd]|[[:space:]:=,]|value)+[0-9][0-9A-Za-z]{5,}' -i
sed -E "s/${tab}[^${tab}]*[Vv][Oo][Uu][Cc][Hh][Ee][Rr][A-Za-z0-9_]*(\\\\?[\"']|%22|%3[AaDd]|[[:space:]:=,]|[Vv][Aa][Ll][Uu][Ee])+/${tab}/" "$tmp/vouchraw" \
  | notallowed "990+[0-9]{1,3}" > "$tmp/voucher"
report "card record voucher" "$tmp/voucher"
echo "pattern scan: $files files, $hits suspicious"

# 2. Value scan
if [ -f "$list" ]; then
  # Drop a UTF-8 BOM, CR and surrounding spaces, blank lines and short numbers
  # (those match everywhere as substrings).
  bom=$(printf '\357\273\277')
  tr -d '\r' < "$list" | sed -e "1s/^$bom//" -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
    | grep -vE '^$|^[0-9]{1,5}$' > "$tmp/values"
  nv=$(grep -c . "$tmp/values")
  if [ "$nv" -eq 0 ]; then
    echo "privacy-check: value list has no usable values (empty, or only short numbers)" >&2
    exit 2
  fi
  gitgrep "$tmp/leakraw" --cached -z -I -i -n -o -F -f "$tmp/values" -- .
  tr '\0' '\t' < "$tmp/leakraw" | awk -F'\t' 'NF >= 3 { print $1 ":" $2 }' | sort -u > "$tmp/leaks"
  n=$(cut -d: -f1 "$tmp/leaks" | sort -u | grep -c .)
  echo "value scan: $nv values, $n files with hits"
  [ "$n" -gt 0 ] && head -50 "$tmp/leaks"
  hits=$((hits+n))
elif [ "$allow_missing" -eq 1 ]; then
  echo "value scan: skipped (no list at LEAKCHECK_FILE; --allow-missing)"
else
  echo "value scan: list not found (set LEAKCHECK_FILE, or pass --allow-missing)" >&2
  exit 2
fi


# 3. Marker scan
markers=${MARKER_PATTERNS:-}
if [ -n "$markers" ] && [ -f "$markers" ]; then
  grep -v '^[[:space:]]*$' "$markers" > "$tmp/markers"
  if ! grep -q . "$tmp/markers"; then echo "privacy-check: marker pattern list is empty" >&2; exit 2; fi
  gitgrep "$tmp/markraw" --cached -z -I -n -E -f "$tmp/markers" -- . ':(exclude)Vendor' \
    ':(exclude)*.png' ':(exclude)*.jpg' ':(exclude)*.jpeg' ':(exclude)*.webp'
  tr '\0' '\t' < "$tmp/markraw" | awk -F'\t' 'NF >= 3 { print $1 ":" $2 }' | sort -u > "$tmp/marks"
  if [ -n "${MARKER_ALLOW:-}" ] && [ -f "$MARKER_ALLOW" ]; then
    grep -v '^[[:space:]]*$' "$MARKER_ALLOW" > "$tmp/allow"
    grep -vxF -f "$tmp/allow" "$tmp/marks" > "$tmp/marks2"; mv "$tmp/marks2" "$tmp/marks"
  fi
  n=$(grep -c . "$tmp/marks")
  echo "marker scan: $n lines"
  [ "$n" -gt 0 ] && head -50 "$tmp/marks"
  hits=$((hits+n))
elif [ -n "$markers" ]; then
  echo "marker scan: pattern list not found at MARKER_PATTERNS" >&2
  exit 2
elif [ "$allow_missing" -eq 1 ]; then
  echo "marker scan: skipped (MARKER_PATTERNS not set; --allow-missing)"
else
  echo "marker scan: MARKER_PATTERNS not set (set it, or pass --allow-missing)" >&2
  exit 2
fi

[ "$hits" -eq 0 ]
