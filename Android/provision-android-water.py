#!/usr/bin/env python3
"""Prepare an authorized local debug test device without embedding a key in APKs.
Only platform fields are accepted. Nothing is printed except completion status.
"""
import argparse
import json
from pathlib import Path
import re
import shlex
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--serial', required=True)
parser.add_argument('--profile', type=Path, default=Path(__file__).resolve().parents[1] / 'private/distribution/WaterPlatformProfile.json')
parser.add_argument('--adb', default='adb')
parser.add_argument('--package', default='com.beamjason.xiaorichang.debug')
args = parser.parse_args()
if not re.fullmatch(r'[A-Za-z0-9_.]+\.debug', args.package):
    parser.error('Only a local debug test package may be prepared')
raw = args.profile.read_bytes()
if len(raw) > 8192:
    parser.error('Profile is too large')
profile = json.loads(raw)
if set(profile) != {'secret', 'sid', 'bleName', 'typeID', 'version'}:
    parser.error('Use a platform-only profile; account, dorm and device fields are forbidden')
if not all(isinstance(profile[k], str) and profile[k].strip() for k in ('secret', 'sid', 'bleName')):
    parser.error('Incomplete platform profile')
if type(profile['typeID']) is not int or not 0 <= profile['typeID'] <= 2147483647 or type(profile['version']) is not int or not 1 <= profile['version'] <= 2147483647:
    parser.error('Invalid protocol fields')
payload = json.dumps(profile, ensure_ascii=False).encode()
operation = 'umask 077; mkdir -p no_backup; cat > no_backup/development-water-platform.json'
remote = 'run-as ' + shlex.quote(args.package) + ' sh -c ' + shlex.quote(operation)
subprocess.run([args.adb, '-s', args.serial, 'shell', '-T', remote], input=payload, check=True, capture_output=True)
print('Private platform staged in the selected debug app. Reopen it to encrypt and consume the one-time file.')
