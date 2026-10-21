#!/bin/bash
# Copies the newest published build(s) into Google Drive (My Drive/Aibox/DungeonCrawlElite). Drive for desktop does the upload.
SRC=${SRC:-$HOME/mnt/grimm--homeai/data/godot_web/_downloads/dungeon-crawl-eliet}
DST=${DST:-$HOME/mnt/My Drive/Aibox/DungeonCrawlElite}
mkdir -p "$DST" || exit 1
for pat in "*.zip" "*.apk"; do
  f=$(ls -t "$SRC"/$pat 2>/dev/null | head -1); [ -z "$f" ] && continue
  b=$(basename "$f"); [ -f "$DST/$b" ] && [ "$(stat -c%s "$f")" = "$(stat -c%s "$DST/$b")" ] && { echo "already: $b"; continue; }
  cp "$f" "$DST/$b.part" && mv "$DST/$b.part" "$DST/$b" && echo "copied: $b"
done
