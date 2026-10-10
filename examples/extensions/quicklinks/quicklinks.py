"""A Fastlight extension in Python: "go gh" opens GitHub.

Links live in $FASTLIGHT_DATA_DIR/links.json ({"name": "url"}), created with
a few examples on first run. Needs python3 (/usr/bin/python3 comes with the
Xcode Command Line Tools). Protocol: docs/extensions/README.md.
"""
import json
import os
import sys

links_file = os.path.join(os.environ.get("FASTLIGHT_DATA_DIR", "."), "links.json")
if not os.path.exists(links_file):
    with open(links_file, "w") as f:
        json.dump({"GitHub": "https://github.com", "Fastlight": "https://github.com/elboletaire/fastlight",
                   "Hacker News": "https://news.ycombinator.com", "Links file": links_file}, f, indent=2)


def send(message):
    print(json.dumps(message), flush=True)


def item(name, url):
    return {"id": name, "title": name, "subtitle": url, "icon": "link",
            "actions": [{"type": "open", "target": url},
                        {"type": "copy", "text": url, "title": "Copy URL"}]}


send({"type": "ready", "protocol": 1})
for line in sys.stdin:  # ends when Fastlight closes our stdin
    request = json.loads(line)
    if "id" not in request:
        continue  # a notification, like "picked": no reply
    if request["type"] != "search":
        send({"id": request["id"], "error": "unsupported request"})
        continue
    with open(links_file) as f:
        links = json.load(f)
    words = request["query"].lower().split()
    found = [item(n, u) for n, u in links.items() if all(w in n.lower() for w in words)]
    send({"id": request["id"], "items": found[: request["limit"]]})
