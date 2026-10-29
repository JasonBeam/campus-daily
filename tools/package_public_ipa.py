#!/usr/bin/env python3
"""Package only an unsigned Release build, never an installed/private Debug app."""
import argparse
import hashlib
import plistlib
import shutil
import subprocess
import tempfile
import zipfile
from pathlib import Path
from stage_platform_profile import validate_profile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--app', required=True, type=Path)
parser.add_argument('--output', required=True, type=Path)
parser.add_argument('--platform-profile', required=True, type=Path,
    help='Explicit local shared-platform profile approved for this no-cloud build')
args = parser.parse_args()
app = args.app.resolve()
if app.parent.name != 'Release-iphoneos' or not app.is_dir():
    parser.error('--app must be an existing Release-iphoneos/*.app')
info = plistlib.loads((app / 'Info.plist').read_bytes())
try:
    expected = validate_profile(args.platform_profile.read_bytes())
    actual = validate_profile((app / 'CampusWaterPlatform.json').read_bytes())
    if actual != expected:
        parser.error('Bundled platform differs from the explicitly supplied local profile')
except (ValueError, OSError):
    parser.error('A validated platform-only resource is required; personal data remains forbidden')
widget = app / 'PlugIns' / 'CampusDailyWidget.appex'
if not widget.is_dir():
    parser.error('CampusDailyWidget extension missing from public app')
for bundle in [app, widget]:
    metadata = plistlib.loads((bundle / 'Info.plist').read_bytes())
    if 'CampusKeychainGroup' in metadata:
        parser.error('Build-time keychain group must not be frozen into an unsigned IPA')
version, build = info['CFBundleShortVersionString'], info['CFBundleVersion']
name = f'CampusDaily-{version}-build{build}-unsigned.ipa'
output = args.output.resolve()
output.mkdir(parents=True, exist_ok=True)
ipa = output / name
if ipa.exists():
    parser.error('output IPA already exists; use a new output directory')
# Inspect every resource and nested extension before creating a distributable.
for path in app.rglob('*'):
    if path.is_symlink():
        parser.error('unexpected symlink in app bundle')
    lower = path.name.lower()
    if lower in {'waterplatformprofile.json', '_codesignature', 'embedded.mobileprovision'} or lower.endswith('water-access.json') or path.suffix.lower() in {'.p12', '.waterconfig', '.campusconfig', '.campuscache', '.laundryconfig', '.har', '.pcap', '.pklg'} or lower.startswith('bootstrap.'):
        parser.error('private configuration or signing material found; refusing package')
    if path.is_file() and path.read_bytes()[:4] in {b'\xcf\xfa\xed\xfe', b'\xfe\xed\xfa\xcf', b'\xca\xfe\xba\xbe'}:
        signature = subprocess.run(['codesign', '-d', str(path)], capture_output=True)
        if signature.returncode == 0:
            parser.error('signed executable found; rebuild with CODE_SIGNING_ALLOWED=NO')
with tempfile.TemporaryDirectory(prefix='campus-public-') as stage:
    target = Path(stage) / 'Payload' / app.name
    shutil.copytree(app, target)
    with zipfile.ZipFile(ipa, 'w', zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(target.rglob('*')):
            if path.is_file():
                archive.write(path, path.relative_to(stage))
with zipfile.ZipFile(ipa) as archive:
    if archive.testzip() is not None:
        raise RuntimeError('IPA ZIP verification failed')
checksum = hashlib.sha256(ipa.read_bytes()).hexdigest()
(output / (name + '.sha256')).write_text(f'{checksum}  {name}\n')
print(f'Created {name}: {ipa.stat().st_size} bytes; ZIP and unsigned resource checks passed')
