#!/usr/bin/env python3
"""Hot-water platform profile: fetch it once, then stage it into a build.

  stage-water-profile.py fetch
      Extract the shared platform profile from the official public Beta 2 IPA
      (checked against the release's SHA-256) into
      private/distribution/WaterPlatformProfile.json (Git-ignored).
      The upstream release notes state that the public IPA carries the shared
      platform parameters (no personal account, dorm or controller data).
      Never commit or share the output.

  stage-water-profile.py stage --profile <json> --output <file>
      Validate an explicitly supplied platform-only profile and write it to
      <file> (the Xcode build phase and the Android build call this).
      Personal data is rejected.
"""
import argparse
import hashlib
import io
import json
import os
import urllib.request
import zipfile
from pathlib import Path


def validate_profile(raw: bytes) -> dict:
    if len(raw) > 8192:
        raise ValueError('Platform profile exceeds 8192 bytes')
    value = json.loads(raw)
    if not isinstance(value, dict) or set(value) != {'secret', 'sid', 'bleName', 'typeID', 'version'}:
        raise ValueError('Use only platform fields; account, dorm and device fields are forbidden')
    for name, maximum in [('secret', 256), ('sid', 128), ('bleName', 64)]:
        text = value[name]
        if not isinstance(text, str) or not text.strip() or len(text.encode()) > maximum or any(ord(c) < 32 or 127 <= ord(c) <= 159 for c in text):
            raise ValueError('Invalid platform text field')
    for name, minimum in [('typeID', 0), ('version', 1)]:
        if type(value[name]) is not int or not minimum <= value[name] <= 2147483647:
            raise ValueError('Invalid platform protocol field')
    return value


def fetch_profile():
    root = Path(__file__).resolve().parents[1]
    output = root / 'private/distribution/WaterPlatformProfile.json'
    base = 'https://github.com/JasonBeam/campus-daily/releases/download/v0.8.0-beta.2/'
    ipa_name = 'CampusDaily-0.8.0-build36-unsigned.ipa'
    member = 'Payload/CampusHotWater.app/CampusWaterPlatform.json'

    if output.exists():
        raise SystemExit(f'{output.relative_to(root)} already exists; keep it, or delete it to fetch again.')

    def fetch(url: str, limit: int) -> bytes:
        with urllib.request.urlopen(url, timeout=60) as response:
            data = response.read(limit + 1)
        if len(data) > limit:
            raise SystemExit('Download exceeds size limit.')
        return data

    checksum = fetch(base + ipa_name + '.sha256', 4096).decode().split()[0].lower()
    ipa = fetch(base + ipa_name, 50 * 1024 * 1024)
    if hashlib.sha256(ipa).hexdigest() != checksum:
        raise SystemExit('SHA-256 mismatch; nothing was written.')
    with zipfile.ZipFile(io.BytesIO(ipa)) as z:
        try:
            raw = z.read(member)
        except KeyError:
            raise SystemExit('The release IPA has no platform profile; nothing was written.')
    try:
        value = validate_profile(raw)
    except ValueError as error:
        raise SystemExit(f'Profile failed validation: {error}')

    output.parent.mkdir(parents=True, exist_ok=True)
    with os.fdopen(os.open(output, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), 'w') as out:
        out.write(raw.decode() if raw.endswith(b'\n') else raw.decode() + '\n')
    print('Shared platform profile saved to private/distribution/ (Git-ignored). Do not commit or share it.')


def stage_profile(parser, args):
    try:
        value = validate_profile(args.profile.read_bytes())
    except (ValueError, OSError):
        parser.error('Supply a valid local platform-only profile; no personal data is permitted')
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(value, ensure_ascii=False, separators=(',', ':')) + '\n')
    print('Shared platform resource staged; no account or controller included')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest='command', required=True)
    commands.add_parser('fetch', help='save the official shared profile to private/distribution/')
    stage = commands.add_parser('stage', help='validate a profile and stage it into a build')
    stage.add_argument('--profile', required=True, type=Path)
    stage.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    if args.command == 'fetch':
        fetch_profile()
    else:
        stage_profile(stage, args)
