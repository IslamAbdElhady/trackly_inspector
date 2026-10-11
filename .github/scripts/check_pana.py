"""Fails if pana reports a lost platform or lost pub.dev points.

Usage: python3 check_pana.py pana.json

Points lost only because a dependency has a newer version are reported as a
warning, so a release elsewhere doesn't block ours.
"""

import json
import sys

PLATFORMS = ['android', 'ios', 'web', 'windows', 'macos', 'linux']

with open(sys.argv[1]) as file:
    pana = json.load(file)

errors = []

tags = set(pana['tags'])
missing = [p for p in PLATFORMS if f'platform:{p}' not in tags]
if missing:
    errors.append(f"Lost platforms: {', '.join(missing)}")

for section in pana['report']['sections']:
    if section['grantedPoints'] == section['maxPoints']:
        continue
    title = (
        f"{section['title']}: "
        f"{section['grantedPoints']}/{section['maxPoints']} points"
    )
    if section['id'] == 'dependency':
        print(f'::warning::{title}')
    else:
        errors.append(title)
    print(section['summary'])

for error in errors:
    print(f'::error::{error}')

scores = pana['scores']
print(f"pub.dev points: {scores['grantedPoints']}/{scores['maxPoints']}")
print(f"Platforms: {', '.join(p for p in PLATFORMS if p not in missing)}")
sys.exit(1 if errors else 0)
