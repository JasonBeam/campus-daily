#!/usr/bin/env python3
"""Make a private, platform-only mobile handoff file. Never upload the output."""
import argparse
import json
import os
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--profile', required=True, type=Path)
parser.add_argument('--output', required=True, type=Path)
args = parser.parse_args()
raw = args.profile.read_bytes()
if len(raw) > 8192:
    parser.error('Profile exceeds the size limit')
value = json.loads(raw)
if set(value) != {'secret', 'sid', 'bleName', 'typeID', 'version'}:
    parser.error('Use a platform-only profile; personal or device fields are forbidden')
for key, limit in [('secret', 256), ('sid', 128), ('bleName', 64)]:
    text = value[key]
    if not isinstance(text, str) or not text.strip() or len(text.encode()) > limit or any(ord(c) < 32 or 127 <= ord(c) <= 159 for c in text):
        parser.error('Invalid platform text fields')
for key, minimum in [('typeID', 0), ('version', 1)]:
    if type(value[key]) is not int or not minimum <= value[key] <= 2147483647:
        parser.error('Invalid protocol fields')
args.output.parent.mkdir(parents=True, exist_ok=True)
with os.fdopen(os.open(args.output, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), 'w') as out:
    json.dump(value, out, ensure_ascii=False)
    out.write('\n')
print('Private mobile handoff file created. Keep it outside GitHub and public downloads.')
