#!/usr/bin/env bash
# Re-stamp the shared CSS/JS links with a content hash.
#
# The Rails middleware serves assets under public/website with
# `cache-control: public, max-age=86400`, so a browser holds the stylesheet for
# 24 hours. Without a changing URL, an edit to caphive.css is simply invisible
# until the cache expires — which is exactly the trap that made several rounds of
# design changes look like they had failed.
#
# Run this after ANY edit to assets/css/caphive.css, assets/js/caphive.js or
# assets/img/caphive-logo.svg:
#
#     ./restamp-assets.sh
#
set -euo pipefail
cd "$(dirname "$0")"
python3 - <<'PY'
import glob, hashlib, re
def v(path):
    return hashlib.md5(open(path, 'rb').read()).hexdigest()[:8]

# (regex-escaped path, attribute the URL sits in) — every long-cached asset
# referenced from the pages needs a stamp, or an edit stays invisible for a day.
ASSETS = [('assets/css/caphive.css', 'href'),
          ('assets/js/caphive.js',   'src'),
          ('assets/img/caphive-logo.svg', 'src')]

vs, n = {}, 0
for path, attr in ASSETS:
    vs[path] = v(path)
for f in sorted(glob.glob('*.html')):
    s = open(f, encoding='utf-8').read(); o = s
    for path, attr in ASSETS:
        s = re.sub(rf'({attr}=")' + re.escape(path) + r'(\?v=[0-9a-f]+)?(")',
                   rf'\g<1>{path}?v={vs[path]}\g<3>', s)
    if s != o:
        open(f, 'w', encoding='utf-8').write(s); n += 1
print('  '.join(f'{p.rsplit("/",1)[1]}?v={h}' for p, h in vs.items()), '-> ', n, 'page(s) updated')
PY
