// TagBridge: a small C API over TagLib, tailored to Taggart's needs.
//
// All strings are UTF-8. Every list returned by a tb_get_* function is owned by
// the caller and must be released with the matching tb_*_list_free function.
// No C++ exceptions cross this boundary.

#ifndef TAGBRIDGE_H
#define TAGBRIDGE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct tb_file tb_file;

typedef enum {
    TB_FORMAT_OTHER = 0,
    TB_FORMAT_MPEG = 1,
    TB_FORMAT_FLAC = 2,
    TB_FORMAT_MP4 = 3,
    TB_FORMAT_OGG_VORBIS = 4,
    TB_FORMAT_OPUS = 5,
} tb_format;

typedef enum {
    TB_CODEC_UNKNOWN = 0,
    TB_CODEC_AAC = 1,
    TB_CODEC_ALAC = 2,
} tb_codec;

typedef enum {
    /// Keep the version of the tag already in the file (ID3v2.2 is written as
    /// 2.3, since TagLib cannot write 2.2). New tags are written as ID3v2.4.
    TB_ID3V2_KEEP = 0,
    TB_ID3V2_3 = 3,
    TB_ID3V2_4 = 4,
} tb_id3v2_version;

typedef struct {
    tb_format format;
    /// The codec inside an MP4 file; unknown for other formats.
    tb_codec codec;
    int length_ms;
    int bitrate_kbps;
    int sample_rate;
    int channels;
    /// 0 when the format has no fixed sample depth (e.g. MP3).
    int bits_per_sample;
    /// Major version of the ID3v2 tag on disk (2, 3 or 4), or 0 if there is none.
    int id3v2_version;
    bool has_id3v1;
    bool read_only;
} tb_info;

typedef struct {
    char *key;
    char **values;
    size_t value_count;
} tb_property;

typedef struct {
    tb_property *items;
    size_t count;
} tb_property_list;

typedef struct {
    uint8_t *data;
    size_t size;
    char *mime_type;
    char *description;
    /// ID3v2 / FLAC picture type; 3 is the front cover.
    int picture_type;
    /// Only meaningful for FLAC; 0 when unknown.
    int width;
    int height;
    int color_depth;
    int num_colors;
} tb_picture;

typedef struct {
    tb_picture *items;
    size_t count;
} tb_picture_list;

typedef struct {
    char **items;
    size_t count;
} tb_string_list;

/// Opens a file for reading and writing tags. Returns NULL on failure, with a
/// message in `error` (which may be NULL).
tb_file *tb_open(const char *path, char *error, size_t error_size);
void tb_close(tb_file *file);

tb_info tb_get_info(const tb_file *file);

/// The file's tags as TagLib's unified property map (e.g. "ARTIST" => ["A", "B"]).
tb_property_list tb_get_properties(const tb_file *file);
/// Replaces the whole property map. Keys not present are removed. Returns the
/// entries the format could not store (usually none); free it with
/// tb_property_list_free.
tb_property_list tb_set_properties(tb_file *file, const tb_property *items, size_t count);
void tb_property_list_free(tb_property_list list);

/// Embedded pictures (FLAC and Ogg PICTURE blocks, ID3v2 APIC frames, MP4
/// covr atoms). MP4 stores no picture type; those are reported as front covers.
tb_picture_list tb_get_pictures(const tb_file *file);
/// Replaces all embedded pictures.
bool tb_set_pictures(tb_file *file, const tb_picture *items, size_t count);
void tb_picture_list_free(tb_picture_list list);

/// The standard ID3v1 genre names, including Winamp's extensions, in genre
/// number order. Free with tb_string_list_free.
tb_string_list tb_id3v1_genres(void);
void tb_string_list_free(tb_string_list list);

/// Writes pending changes to disk. For MP3 files only the ID3v2 tag and an
/// already existing ID3v1/APE tag are written; ID3v1 is never created.
bool tb_save(tb_file *file, tb_id3v2_version id3v2_version, char *error, size_t error_size);

#ifdef __cplusplus
}
#endif

#endif
