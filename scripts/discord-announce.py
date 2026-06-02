#!/usr/bin/env python3
"""
Post a push announcement to Discord as a rich embed.

Usage:
  BODY='...' DISCORD_TOKEN='...' python3 scripts/discord-announce.py

The BODY env var should contain lines:
  line 1: title (bold markdown)
  line 2: empty
  line 3+: description paragraphs
  last line: link
"""

import os
import sys
import json
import urllib.request
import urllib.error


def build_body_from_github_event():
    """Read GitHub event payload from GITHUB_EVENT_PATH and build a summary."""
    event_path = os.environ.get("GITHUB_EVENT_PATH")
    if not event_path or not os.path.exists(event_path):
        return os.environ.get("BODY", "")

    with open(event_path) as f:
        event = json.load(f)

    repo = event.get("repository", {}).get("full_name", "opencpo/opencpo")
    ref = event.get("ref", "refs/heads/main")
    branch = ref.replace("refs/heads/", "")
    actor = event.get("sender", {}).get("login", "unknown")
    compare = event.get("compare", "")
    commits = event.get("commits", [])

    lines = []
    lines.append(f"**{repo}** — push to `{branch}` by **{actor}**")
    lines.append("")

    for c in commits[:5]:
        msg = c.get("message", "").split("\n")[0][:120]
        sha = c.get("id", "???????")[:7]
        url = c.get("url", "")
        author = c.get("author", {}).get("username", "unknown")
        lines.append(f"  [`{sha}`]({url}) {msg} — {author}")

    if len(commits) > 5:
        lines.append(f"  … and {len(commits)-5} more commits")

    lines.append("")
    lines.append(f"[View compare]({compare})")

    return "\n".join(lines)


def post_to_discord(body):
    token = os.environ.get("DISCORD_TOKEN")
    channel = os.environ.get("DISCORD_CHANNEL", "1511324094015209636")

    if not token:
        print("DISCORD_TOKEN not set", file=sys.stderr)
        return False

    if not body:
        print("BODY is empty — nothing to post", file=sys.stderr)
        return False

    lines = body.split("\n")
    title = lines[0] if lines else "Push to opencpo"
    desc = "\n".join(lines[1:]).strip()

    payload = {
        "embeds": [
            {
                "title": title,
                "description": desc,
                "color": 0x00CED1,
            }
        ]
    }

    data = json.dumps(payload).encode()
    req = urllib.request.Request(
        f"https://discord.com/api/v10/channels/{channel}/messages",
        data=data,
        method="POST",
        headers={
            "Authorization": f"Bot {token}",
            "Content-Type": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(req) as r:
            result = json.load(r)
            print(f"Posted as message {result['id']}")
            return True
    except urllib.error.HTTPError as e:
        print(f"Discord API error {e.code}: {e.read().decode()}", file=sys.stderr)
        return False


def main():
    body = build_body_from_github_event()
    if post_to_discord(body):
        sys.exit(0)
    else:
        sys.exit(1)


if __name__ == "__main__":
    main()
