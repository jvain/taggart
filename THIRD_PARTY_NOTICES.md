# Third-party software

Taggart's own code is MIT licensed (see `LICENSE`). Builds of the app include
the following libraries, which keep their own licenses. The license texts are
in `Resources/Licenses` and are copied into every app bundle, under
`Taggart.app/Contents/Resources/Licenses`.

## TagLib

- Project: https://taglib.org — source at https://github.com/taglib/taglib
- Packaged for SwiftPM by https://github.com/sbooth/CXXTagLib (version pinned in `Package.resolved`)
- License: dual-licensed under the GNU Lesser General Public License 2.1
  (LGPL-2.1) and the Mozilla Public License 1.1 (MPL-1.1). The MPL-1.1 text is
  in `Resources/Licenses/TagLib-MPL-1.1.txt`.

TagLib's source code, including any modifications, is available from the
links above. Taggart doesn't modify it.

## UTF8-CPP (bundled with TagLib)

- Project: https://github.com/nemtrif/utfcpp
- License: Boost Software License 1.0 (`Resources/Licenses/utfcpp-BSL-1.0.txt`)

# Online data

Looking up albums uses two free services; nothing is sent except the search
(album and artist names, or a release ID).

- **MusicBrainz** (https://musicbrainz.org): its music data is in the public
  domain (CC0). Taggart identifies itself to it and makes at most one request
  per second, as its API rules ask.
- **Cover Art Archive** (https://coverartarchive.org): cover images uploaded
  by MusicBrainz users. The images remain their copyright holders'.
