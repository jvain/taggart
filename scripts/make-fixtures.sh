#!/bin/sh
# Regenerates the tiny audio files used by the tests. The outputs are committed,
# so this only needs to run when fixtures change. Requires: brew install ffmpeg flac
set -eu

out="$(cd "$(dirname "$0")/.." && pwd)/Tests/TaggartCoreTests/Fixtures"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$out"

ff() { ffmpeg -nostdin -hide_banner -loglevel error -y "$@"; }

# Images: a red PNG cover, a green JPEG back cover, a blue JPEG for tests to embed.
ff -f lavfi -i color=c=red:s=64x64 -frames:v 1 "$work/red.png"
ff -f lavfi -i color=c=green:s=48x48 -frames:v 1 "$work/green.jpg"
ff -f lavfi -i color=c=blue:s=32x32 -frames:v 1 "$out/blue.jpg"

silence="-f lavfi -t 1 -i anullsrc=r=44100:cl=stereo"

# FLAC with multi-value artist, separate track total and a custom tag.
ff $silence -c:a flac "$out/basic.flac"
metaflac --remove-all-tags \
    --set-tag=TITLE="Flac Title" \
    --set-tag=ARTIST="Artist One" --set-tag=ARTIST="Artist Two" \
    --set-tag=ALBUM="Flac Album" \
    --set-tag=TRACKNUMBER=3 --set-tag=TRACKTOTAL=12 \
    --set-tag=DISCNUMBER=1 --set-tag=DISCTOTAL=2 \
    --set-tag=DATE=2001 --set-tag=GENRE=Ambient \
    --set-tag=CUSTOM_KEY="keep me" \
    "$out/basic.flac"

# FLAC with a front cover and a back cover.
ff $silence -c:a flac "$out/cover.flac"
metaflac --remove-all-tags --set-tag=TITLE="Covered" \
    --import-picture-from="3|image/png|Front||$work/red.png" \
    --import-picture-from="4|image/jpeg|Back||$work/green.jpg" \
    "$out/cover.flac"

# MP3 with ID3v2.4, "n/total" track number and a custom TXXX frame.
ff $silence -c:a libmp3lame -b:a 128k -id3v2_version 4 \
    -metadata title="Mp3 Title" -metadata artist="Mp3 Artist" -metadata album="Mp3 Album" \
    -metadata track=5/9 -metadata date=1999 -metadata CUSTOM_KEY="keep me" \
    "$out/basic.mp3"

# MP3 with ID3v2.3 plus an ID3v1 tag.
ff $silence -c:a libmp3lame -b:a 128k -id3v2_version 3 -write_id3v1 1 \
    -metadata title="Legacy Title" -metadata artist="Legacy Artist" -metadata track=2 \
    "$out/legacy.mp3"

# MP3 with ID3v2.3 and an embedded front cover.
ff $silence -i "$work/red.png" -map 0:a -map 1:v -c:a libmp3lame -b:a 128k -c:v copy \
    -id3v2_version 3 -metadata title="Covered Mp3" \
    -metadata:s:v title="Front" -metadata:s:v comment="Cover (front)" \
    "$out/cover.mp3"

ls -l "$out"
