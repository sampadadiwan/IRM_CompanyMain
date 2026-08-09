#!/usr/bin/env bash
# Re-stamp the shared CSS/JS links with a content hash.
#
# The Rails middleware serves assets under public/website with
# `cache-control: public, max-age=86400`, so a browser holds the stylesheet for
# 24 hours. Without a changing URL, an edit to caphive.css is simply invisible
# until the cache expires — which is exactly the trap that made several rounds of
# design changes look like they had failed.
#
# Run this after ANY edit to assets/css/caphive.css or assets/js/caphive.js:
#
#     ./restamp-assets.sh
#
set -euo pipefail
cd "$(dirname "$0")"
python3 - <<'PY'
import glob, hashlib, re
css_v = hashlib.md5(open('assets/css/caphive.css','rb').read()).hexdigest()[:8]
js_v  = hashlib.md5(open('assets/js/caphive.js','rb').read()).hexdigest()[:8]
n = 0
for f in sorted(glob.glob('*.html')):
    s = open(f, encoding='utf-8').read(); o = s
    s = re.sub(r'(href=")assets/css/caphive\.css(\?v=[0-9a-f]+)?(")',
               rf'\1assets/css/caphive.css?v={css_v}\3', s)
    s = re.sub(r'(src=")assets/js/caphive\.js(\?v=[0-9a-f]+)?(")',
               rf'\1assets/js/caphive.js?v={js_v}\3', s)
    if s != o:
        open(f, 'w', encoding='utf-8').write(s); n += 1
print(f"css?v={css_v}  js?v={js_v}  ->  {n} page(s) updated")
PY
