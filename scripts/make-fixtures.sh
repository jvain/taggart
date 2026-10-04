#!/bin/sh
# Makes the tiny audio files used by the tests. The outputs are committed, so
# this only needs to run when fixtures are added or changed. By default only
# missing fixtures are made, so existing ones don't change needlessly;
# --force remakes them all. Requires: brew install ffmpeg flac (and python3,
# which comes with the Command Line Tools).
set -eu

out="$(cd "$(dirname "$0")/.." && pwd)/Tests/TaggartCoreTests/Fixtures"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$out"

force=0
[ "${1:-}" = "--force" ] && force=1

# True if the fixture should be made now.
missing() {
    [ "$force" = 1 ] || [ ! -e "$out/$1" ]
}

ff() { ffmpeg -nostdin -hide_banner -loglevel error -y "$@"; }

# Images: a red PNG cover, a green JPEG back cover, a blue JPEG for tests to embed.
ff -f lavfi -i color=c=red:s=64x64 -frames:v 1 "$work/red.png"
ff -f lavfi -i color=c=green:s=48x48 -frames:v 1 "$work/green.jpg"
if missing blue.jpg; then
    ff -f lavfi -i color=c=blue:s=32x32 -frames:v 1 "$out/blue.jpg"
fi

silence="-f lavfi -t 1 -i anullsrc=r=44100:cl=stereo"

# FLAC with multi-value artist, separate track total and a custom tag.
if missing basic.flac; then
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
fi

# FLAC with a front cover and a back cover.
if missing cover.flac; then
    ff $silence -c:a flac "$out/cover.flac"
    metaflac --remove-all-tags --set-tag=TITLE="Covered" \
        --import-picture-from="3|image/png|Front||$work/red.png" \
        --import-picture-from="4|image/jpeg|Back||$work/green.jpg" \
        "$out/cover.flac"
fi

# MP3 with ID3v2.4, "n/total" track number and a custom TXXX frame.
if missing basic.mp3; then
    ff $silence -c:a libmp3lame -b:a 128k -id3v2_version 4 \
        -metadata title="Mp3 Title" -metadata artist="Mp3 Artist" -metadata album="Mp3 Album" \
        -metadata track=5/9 -metadata date=1999 -metadata CUSTOM_KEY="keep me" \
        "$out/basic.mp3"
fi

# MP3 with ID3v2.3 plus an ID3v1 tag.
if missing legacy.mp3; then
    ff $silence -c:a libmp3lame -b:a 128k -id3v2_version 3 -write_id3v1 1 \
        -metadata title="Legacy Title" -metadata artist="Legacy Artist" -metadata track=2 \
        "$out/legacy.mp3"
fi

# MP3 with ID3v2.3 and an embedded front cover.
if missing cover.mp3; then
    ff $silence -i "$work/red.png" -map 0:a -map 1:v -c:a libmp3lame -b:a 128k -c:v copy \
        -id3v2_version 3 -metadata title="Covered Mp3" \
        -metadata:s:v title="Front" -metadata:s:v comment="Cover (front)" \
        "$out/cover.mp3"
fi

# M4A (AAC) with "n/total" track and disc numbers.
if missing basic.m4a; then
    ff $silence -c:a aac -b:a 128k \
        -metadata title="M4a Title" -metadata artist="M4a Artist" -metadata album="M4a Album" \
        -metadata album_artist="M4a Band" -metadata track=4/10 -metadata disc=1/2 \
        -metadata date=2005 -metadata genre=Jazz \
        "$out/basic.m4a"
fi

# M4A (Apple Lossless) with a cover.
if missing cover.m4a; then
    ff $silence -i "$work/red.png" -map 0:a -map 1:v -c:a alac -c:v copy \
        -disposition:v attached_pic -metadata title="Covered M4a" \
        "$out/cover.m4a"
fi

# Ogg Vorbis with a separate track total and a custom tag. (Homebrew's ffmpeg
# lacks libvorbis; its own encoder is marked experimental but fine for this.)
if missing basic.ogg; then
    ff $silence -c:a vorbis -strict experimental \
        -metadata TITLE="Ogg Title" -metadata ARTIST="Ogg Artist" -metadata ALBUM="Ogg Album" \
        -metadata TRACKNUMBER=2 -metadata TRACKTOTAL=7 -metadata CUSTOM_KEY="keep me" \
        "$out/basic.ogg"
fi

# Opus with a custom tag.
if missing basic.opus; then
    ff $silence -c:a libopus -b:a 64k \
        -metadata TITLE="Opus Title" -metadata ARTIST="Opus Artist" \
        -metadata TRACKNUMBER=6 -metadata CUSTOM_KEY="keep me" \
        "$out/basic.opus"
fi

# Uncompressed formats are kept short, so the files stay small.
short="-f lavfi -t 0.1 -i anullsrc=r=44100:cl=stereo"

# WAV with only a RIFF INFO tag (what ffmpeg writes).
if missing basic.wav; then
    ff $short -c:a pcm_s16le \
        -metadata title="Wav Title" -metadata artist="Wav Artist" -metadata album="Wav Album" \
        -metadata track=8 -metadata date=2010 -metadata genre=Rock \
        "$out/basic.wav"
fi

# AIFF with an ID3v2.4 tag, "n/total" track number and a custom tag.
if missing basic.aiff; then
    ff $short -c:a pcm_s16be -write_id3v2 1 -id3v2_version 4 \
        -metadata title="Aiff Title" -metadata artist="Aiff Artist" -metadata album="Aiff Album" \
        -metadata track=5/9 -metadata date=1999 -metadata CUSTOM_KEY="keep me" \
        "$out/basic.aiff"
fi

# WavPack with an APEv2 tag.
if missing basic.wv; then
    ff $silence -c:a wavpack -sample_fmt s16p \
        -metadata title="Wv Title" -metadata artist="Wv Artist" -metadata album="Wv Album" \
        -metadata track=3/12 -metadata date=2003 -metadata CUSTOM_KEY="keep me" \
        "$out/basic.wv"
fi

# Monkey's Audio, untagged. ffmpeg can't encode it, so this is a valid header
# (version 3.99, 16-bit stereo, 44.1 kHz, one 1-second frame) followed by
# zeros in place of audio: enough for TagLib, which reads only the header and
# the tags.
if missing basic.ape; then
    python3 - "$out/basic.ape" <<'PY'
import struct, sys
audio = 4096
descriptor = b"MAC " + struct.pack("<HH7I", 3990, 0, 52, 24, 0, 0, audio, 0, 0) + bytes(16)
header = struct.pack("<HHIIIHHI", 2000, 0, 73728, 44100, 1, 16, 2, 44100)
open(sys.argv[1], "wb").write(descriptor + header + bytes(audio))
PY
fi

# WMA with tags in both of its tag objects.
if missing basic.wma; then
    ff $silence -c:a wmav2 -b:a 64k \
        -metadata title="Wma Title" -metadata artist="Wma Artist" -metadata album="Wma Album" \
        -metadata track=7 -metadata date=2007 -metadata genre=Pop \
        "$out/basic.wma"
fi

ls -l "$out"
