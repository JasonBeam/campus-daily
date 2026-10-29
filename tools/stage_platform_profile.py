#!/usr/bin/env python3
"""Stage an explicitly supplied shared platform profile; personal data is rejected."""
import argparse
import json
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


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--profile', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    try:
        value = validate_profile(args.profile.read_bytes())
    except (ValueError, OSError):
        parser.error('Supply a valid local platform-only profile; no personal data is permitted')
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(value, ensure_ascii=False, separators=(',', ':')) + '\n')
    print('Shared platform resource staged; no account or controller included')
