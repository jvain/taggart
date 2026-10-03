#include "TagBridge.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <new>
#include <string>

#include <taglib/fileref.h>
#include <taglib/id3v1genres.h>
#include <taglib/flacfile.h>
#include <taglib/flacproperties.h>
#include <taglib/id3v2header.h>
#include <taglib/id3v2tag.h>
#include <taglib/mpegfile.h>
#include <taglib/tpicturetype.h>
#include <taglib/tpropertymap.h>
#include <taglib/tvariant.h>

struct tb_file {
    TagLib::FileRef ref;
    int id3v2Version = 0;
};

namespace {

const TagLib::String kPictureKey("PICTURE");
constexpr int kMaxPictureType = 20;  // Publisher logo

void setError(char *error, size_t size, const char *message) {
    if(error && size > 0)
        std::snprintf(error, size, "%s", message);
}

char *copyString(const TagLib::String &string) {
    const std::string utf8 = string.to8Bit(true);
    auto out = static_cast<char *>(std::malloc(utf8.size() + 1));
    if(!out)
        throw std::bad_alloc();
    std::memcpy(out, utf8.c_str(), utf8.size() + 1);
    return out;
}

TagLib::String fromUTF8(const char *string) {
    return string ? TagLib::String(string, TagLib::String::UTF8) : TagLib::String();
}

TagLib::MPEG::File *mpegFile(const tb_file *file) {
    return dynamic_cast<TagLib::MPEG::File *>(file->ref.file());
}

int currentID3v2Version(TagLib::MPEG::File *mpeg) {
    if(!mpeg || !mpeg->hasID3v2Tag() || !mpeg->ID3v2Tag())
        return 0;
    return static_cast<int>(mpeg->ID3v2Tag()->header()->majorVersion());
}

tb_property_list toPropertyList(const TagLib::PropertyMap &map) {
    tb_property_list list { nullptr, 0 };
    if(map.isEmpty())
        return list;
    try {
        list.items = static_cast<tb_property *>(std::calloc(map.size(), sizeof(tb_property)));
        if(!list.items)
            throw std::bad_alloc();
        for(const auto &[key, values] : map) {
            tb_property &property = list.items[list.count++];
            property.key = copyString(key);
            property.values = static_cast<char **>(std::calloc(values.isEmpty() ? 1 : values.size(), sizeof(char *)));
            if(!property.values)
                throw std::bad_alloc();
            for(const auto &value : values)
                property.values[property.value_count++] = copyString(value);
        }
    }
    catch(...) {
        tb_property_list_free(list);
        list = { nullptr, 0 };
    }
    return list;
}

}  // namespace

extern "C" {

tb_file *tb_open(const char *path, char *error, size_t error_size) {
    try {
        auto file = new tb_file { TagLib::FileRef(path, true, TagLib::AudioProperties::Average) };
        // TagLib accepts any file with an .mp3 extension as MPEG; require an
        // actual audio frame so tags are never written into non-audio files.
        auto mpeg = mpegFile(file);
        if(file->ref.isNull() || !file->ref.file()->isValid() || (mpeg && mpeg->firstFrameOffset() < 0)) {
            delete file;
            setError(error, error_size, "The file is not a supported audio file or could not be read.");
            return nullptr;
        }
        file->id3v2Version = currentID3v2Version(mpeg);
        return file;
    }
    catch(const std::exception &e) {
        setError(error, error_size, e.what());
    }
    catch(...) {
        setError(error, error_size, "Unknown error while opening the file.");
    }
    return nullptr;
}

void tb_close(tb_file *file) {
    delete file;
}

tb_info tb_get_info(const tb_file *file) {
    tb_info info {};
    TagLib::File *f = file->ref.file();
    info.read_only = f->readOnly();
    if(auto mpeg = mpegFile(file)) {
        info.format = TB_FORMAT_MPEG;
        info.id3v2_version = file->id3v2Version;
        info.has_id3v1 = mpeg->hasID3v1Tag();
    }
    else if(dynamic_cast<TagLib::FLAC::File *>(f)) {
        info.format = TB_FORMAT_FLAC;
    }
    if(const TagLib::AudioProperties *properties = file->ref.audioProperties()) {
        info.length_ms = properties->lengthInMilliseconds();
        info.bitrate_kbps = properties->bitrate();
        info.sample_rate = properties->sampleRate();
        info.channels = properties->channels();
        if(auto flac = dynamic_cast<const TagLib::FLAC::Properties *>(properties))
            info.bits_per_sample = flac->bitsPerSample();
    }
    return info;
}

tb_property_list tb_get_properties(const tb_file *file) {
    try {
        return toPropertyList(file->ref.properties());
    }
    catch(...) {
        return { nullptr, 0 };
    }
}

tb_property_list tb_set_properties(tb_file *file, const tb_property *items, size_t count) {
    try {
        TagLib::PropertyMap map;
        for(size_t i = 0; i < count; ++i) {
            TagLib::StringList values;
            for(size_t j = 0; j < items[i].value_count; ++j)
                values.append(fromUTF8(items[i].values[j]));
            map.insert(fromUTF8(items[i].key), values);
        }
        return toPropertyList(file->ref.setProperties(map));
    }
    catch(...) {
        return { nullptr, 0 };
    }
}

void tb_property_list_free(tb_property_list list) {
    for(size_t i = 0; i < list.count; ++i) {
        tb_property &property = list.items[i];
        std::free(property.key);
        if(property.values) {
            for(size_t j = 0; j < property.value_count; ++j)
                std::free(property.values[j]);
            std::free(property.values);
        }
    }
    std::free(list.items);
}

tb_picture_list tb_get_pictures(const tb_file *file) {
    tb_picture_list list { nullptr, 0 };
    try {
        TagLib::List<TagLib::VariantMap> pictures;
        if(auto mpeg = mpegFile(file))
            pictures = mpeg->ID3v2Tag() ? mpeg->ID3v2Tag()->complexProperties(kPictureKey) : pictures;
        else
            pictures = file->ref.complexProperties(kPictureKey);
        if(pictures.isEmpty())
            return list;

        list.items = static_cast<tb_picture *>(std::calloc(pictures.size(), sizeof(tb_picture)));
        if(!list.items)
            throw std::bad_alloc();
        for(const auto &properties : pictures) {
            tb_picture &picture = list.items[list.count++];
            const TagLib::ByteVector data = properties.value("data").value<TagLib::ByteVector>();
            picture.data = static_cast<uint8_t *>(std::malloc(data.isEmpty() ? 1 : data.size()));
            if(!picture.data)
                throw std::bad_alloc();
            std::memcpy(picture.data, data.data(), data.size());
            picture.size = data.size();
            picture.mime_type = copyString(properties.value("mimeType").value<TagLib::String>());
            picture.description = copyString(properties.value("description").value<TagLib::String>());
            picture.picture_type = TagLib::Utils::pictureTypeFromString(properties.value("pictureType").value<TagLib::String>());
            picture.width = properties.value("width").value<int>();
            picture.height = properties.value("height").value<int>();
            picture.color_depth = properties.value("colorDepth").value<int>();
            picture.num_colors = properties.value("numColors").value<int>();
        }
    }
    catch(...) {
        tb_picture_list_free(list);
        list = { nullptr, 0 };
    }
    return list;
}

bool tb_set_pictures(tb_file *file, const tb_picture *items, size_t count) {
    try {
        TagLib::List<TagLib::VariantMap> pictures;
        for(size_t i = 0; i < count; ++i) {
            const tb_picture &picture = items[i];
            int type = picture.picture_type;
            if(type < 0 || type > kMaxPictureType)
                type = 0;
            TagLib::VariantMap properties;
            properties.insert("data", TagLib::ByteVector(reinterpret_cast<const char *>(picture.data),
                                                         static_cast<unsigned int>(picture.size)));
            properties.insert("mimeType", fromUTF8(picture.mime_type));
            properties.insert("description", fromUTF8(picture.description));
            properties.insert("pictureType", TagLib::Utils::pictureTypeToString(type));
            properties.insert("width", picture.width);
            properties.insert("height", picture.height);
            properties.insert("colorDepth", picture.color_depth);
            properties.insert("numColors", picture.num_colors);
            pictures.append(properties);
        }
        // For MP3, write to the ID3v2 tag only (creating it if needed) so that
        // APE tags are left alone.
        if(auto mpeg = mpegFile(file))
            return mpeg->ID3v2Tag(true)->setComplexProperties(kPictureKey, pictures);
        return file->ref.setComplexProperties(kPictureKey, pictures);
    }
    catch(...) {
        return false;
    }
}

void tb_picture_list_free(tb_picture_list list) {
    for(size_t i = 0; i < list.count; ++i) {
        std::free(list.items[i].data);
        std::free(list.items[i].mime_type);
        std::free(list.items[i].description);
    }
    std::free(list.items);
}

tb_string_list tb_id3v1_genres(void) {
    tb_string_list list { nullptr, 0 };
    try {
        const TagLib::StringList genres = TagLib::ID3v1::genreList();
        list.items = static_cast<char **>(std::calloc(genres.isEmpty() ? 1 : genres.size(), sizeof(char *)));
        if(!list.items)
            throw std::bad_alloc();
        for(const auto &genre : genres)
            list.items[list.count++] = copyString(genre);
    }
    catch(...) {
        tb_string_list_free(list);
        list = { nullptr, 0 };
    }
    return list;
}

void tb_string_list_free(tb_string_list list) {
    for(size_t i = 0; i < list.count; ++i)
        std::free(list.items[i]);
    std::free(list.items);
}

bool tb_save(tb_file *file, tb_id3v2_version id3v2_version, char *error, size_t error_size) {
    try {
        if(file->ref.file()->readOnly()) {
            setError(error, error_size, "The file is read-only.");
            return false;
        }
        bool saved;
        if(auto mpeg = mpegFile(file)) {
            int tags = TagLib::MPEG::File::ID3v2;
            if(mpeg->hasID3v1Tag())
                tags |= TagLib::MPEG::File::ID3v1;
            if(mpeg->hasAPETag())
                tags |= TagLib::MPEG::File::APE;

            TagLib::ID3v2::Version version = TagLib::ID3v2::v4;
            if(id3v2_version == TB_ID3V2_3 || (id3v2_version == TB_ID3V2_KEEP && (file->id3v2Version == 2 || file->id3v2Version == 3)))
                version = TagLib::ID3v2::v3;

            // DoNotDuplicate: setProperties already keeps an existing ID3v1 tag in
            // sync, and duplicating would copy stale ID3v1 values back into ID3v2.
            saved = mpeg->save(tags, TagLib::File::StripNone, version, TagLib::File::DoNotDuplicate);
            if(saved)
                file->id3v2Version = currentID3v2Version(mpeg);
        }
        else {
            saved = file->ref.save();
        }
        if(!saved)
            setError(error, error_size, "TagLib could not write the tags.");
        return saved;
    }
    catch(const std::exception &e) {
        setError(error, error_size, e.what());
    }
    catch(...) {
        setError(error, error_size, "Unknown error while saving the file.");
    }
    return false;
}

}  // extern "C"
