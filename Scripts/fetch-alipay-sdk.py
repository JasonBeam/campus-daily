#!/usr/bin/env python3
"""Fetch the pinned official SDK without executing downloaded code."""
from pathlib import Path, PurePosixPath
import hashlib
import io
import json
import shutil
import tempfile
import urllib.request
import zipfile

root = Path(__file__).resolve().parents[1]
target = root / 'Vendor/AlipaySDK-15.8.30'
source = json.loads((target / 'source.json').read_text())
url = source['podspec']['source']['http']
expected = source['archiveSHA256']
if url != 'https://mdn.alipayobjects.com/mobilecashier_res/afts/file/lEoLQ64WOGAAAAAAAAAAAAAADnW6AQBr':
    raise SystemExit('Unexpected source URL; inspect source.json before downloading.')
names = ('AlipaySDK.xcframework', 'AlipaySDK.bundle')
if any((target / name).exists() for name in names):
    raise SystemExit('SDK destination already exists; keep it intact and inspect it manually.')
with urllib.request.urlopen(url, timeout=60) as response:
    archive = response.read(50 * 1024 * 1024 + 1)
if len(archive) > 50 * 1024 * 1024:
    raise SystemExit('Archive exceeds size limit.')
actual = hashlib.sha256(archive).hexdigest()
if actual != expected:
    raise SystemExit('SHA-256 mismatch; SDK was not extracted.')
with zipfile.ZipFile(io.BytesIO(archive)) as z, tempfile.TemporaryDirectory() as work:
    for item in z.infolist():
        parts = PurePosixPath(item.filename)
        if parts.is_absolute() or '..' in parts.parts or ((item.external_attr >> 16) & 0o170000) == 0o120000:
            raise SystemExit('Unsafe archive member; SDK was not extracted.')
    if sum(x.file_size for x in z.infolist()) > 200 * 1024 * 1024:
        raise SystemExit('Expanded archive exceeds size limit.')
    members = [x for x in z.infolist() if "__MACOSX" not in PurePosixPath(x.filename).parts and not any(p.startswith("._") for p in PurePosixPath(x.filename).parts)]
    z.extractall(work, members=members)
    found = {}
    for name in names:
        candidates = [x for x in Path(work).rglob(name) if x.is_dir() and not any(p in names for p in x.relative_to(work).parts[:-1])]
        if len(candidates) != 1:
            raise SystemExit('Expected one top-level ' + name + '; inspect official archive.')
        found[name] = candidates[0]
    for name, path in found.items():
        shutil.copytree(path, target / name)
print('Official AlipaySDK-iOS 15.8.30 downloaded; SHA-256 verified.')
