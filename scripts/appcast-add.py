"""Adds one release to Caution Flag's Sparkle appcast (creating the file if needed).

Usage: appcast-add.py <appcast.xml> <version> <build> <zip-url> '<sign_update output>'
The sign_update output looks like: sparkle:edSignature="..." length="12345"
Newest item goes first; an existing item for the same build is replaced.
"""
import re
import sys
from email.utils import formatdate
from pathlib import Path
from xml.sax.saxutils import escape, quoteattr

path, version, build, url, attrs = sys.argv[1:6]
sig = re.search(r'sparkle:edSignature="([^"]+)"', attrs)
length = re.search(r'length="(\d+)"', attrs)
if not sig or not length:
    sys.exit(f"unexpected sign_update output: {attrs!r}")

item = f"""    <item>
      <title>Version {escape(version)}</title>
      <pubDate>{formatdate(usegmt=True)}</pubDate>
      <sparkle:version>{escape(build)}</sparkle:version>
      <sparkle:shortVersionString>{escape(version)}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>
      <enclosure url={quoteattr(url)} sparkle:edSignature={quoteattr(sig.group(1))} length="{length.group(1)}" type="application/octet-stream"/>
    </item>
"""

file = Path(path)
if file.exists():
    text = file.read_text()
else:
    text = """<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Caution Flag</title>
    <link>https://github.com/taylorbird/homebrew-caution-flag</link>
    <description>Caution Flag updates</description>
    <language>en</language>
  </channel>
</rss>
"""

# Drop an earlier item for the same build (a re-run of the same release).
text = re.sub(
    r"    <item>\n(?:(?!    </item>).)*?<sparkle:version>" + re.escape(build) + r"</sparkle:version>.*?    </item>\n",
    "", text, flags=re.S)
marker = "    <language>en</language>\n"
if marker not in text:
    sys.exit("appcast.xml has an unexpected shape; edit it by hand")
text = text.replace(marker, marker + item, 1)
file.write_text(text)
print(f"appcast: added {version} (build {build})")
