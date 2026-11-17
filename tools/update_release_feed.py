#!/usr/bin/env python3
"""Reduce a published GitHub release JSON to public update metadata for Pages."""
import argparse
import json
import re
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--release-json', type=Path, required=True)
parser.add_argument('--output', type=Path, default=Path('docs/updates.json'))
args = parser.parse_args()
release = json.loads(args.release_json.read_bytes())
tag = release.get('tag_name', '')
if not re.fullmatch(r'v[0-9]+\.[0-9]+\.[0-9]+', tag) or release.get('draft') is not False or release.get('prerelease') is not False:
    parser.error('Only a published stable release may be advertised')
if release.get('html_url') != 'https://github.com/JasonBeam/campus-daily/releases/tag/' + tag:
    parser.error('Unexpected release origin')
assets = [{'name': item['name']} for item in release['assets'] if isinstance(item.get('name'), str)]
if not any(re.fullmatch(r'CampusDaily-.+-build[0-9]+-unsigned\.ipa', item['name']) for item in assets):
    parser.error('Published iOS package is missing')
if not any(re.fullmatch(r'CampusDaily-.+-code[0-9]+-(debug|release)\.apk', item['name']) for item in assets):
    parser.error('Published Android package with versionCode is missing')
result = {key: release[key] for key in ('tag_name', 'html_url', 'draft', 'prerelease')}
result['assets'] = assets
args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
print('Public update metadata written for', tag)
