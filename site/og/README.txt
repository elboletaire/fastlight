og.html is the source of ../og.png (1200x630). To re-render, serve site/ and
screenshot it with headless Chrome (from the repo root):

  python3 -m http.server -d site 8765 &
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new \
    --hide-scrollbars --force-device-scale-factor=1 --window-size=1200,630 \
    --virtual-time-budget=5000 --screenshot=site/og.png http://localhost:8765/og/og.html
  # Keep it under ~300 KB (the current render is ~190 KB).

GitHub repository social preview (1280x640, upload it under the repo's
Settings → Social preview), same source at another size:

  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new \
    --hide-scrollbars --force-device-scale-factor=1 --window-size=1280,640 \
    --virtual-time-budget=5000 --screenshot=site/og/github-social-preview.png \
    "http://localhost:8765/og/og.html?size=github"
