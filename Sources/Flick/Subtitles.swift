import Foundation

struct SubtitleTrack: Equatable {
    var id: Int
    var language: String?
    var isSelected: Bool

    static func tracks(inTrackList json: String) -> [SubtitleTrack] {
        struct Entry: Decodable {
            var id: Int
            var type: String
            var lang: String?
            var selected: Bool?
        }
        guard let data = json.data(using: .utf8), let entries = try? JSONDecoder().decode([Entry].self, from: data) else { return [] }
        return entries.filter { $0.type == "sub" }.map { SubtitleTrack(id: $0.id, language: $0.lang, isSelected: $0.selected ?? false) }
    }

    static func preferred(among tracks: [SubtitleTrack], languages: [String]) -> SubtitleTrack? {
        let wanted = languages.compactMap(baseLanguage)
        return tracks.min { rank($0, in: wanted) < rank($1, in: wanted) }
    }

    private static func rank(_ track: SubtitleTrack, in languages: [String]) -> Int {
        track.language.flatMap(baseLanguage).flatMap(languages.firstIndex(of:)) ?? languages.count
    }

    static func baseLanguage(_ identifier: String) -> String? {
        let language = Locale.Language(identifier: identifier).languageCode
        return language?.identifier(.alpha2) ?? language?.identifier
    }
}

enum WebSubtitles {
    static func ytdlRawOptions(languages: [String]) -> String {
        var codes: [String] = []
        for code in languages.compactMap(SubtitleTrack.baseLanguage) + ["en"] where !codes.contains(code) {
            codes.append(code)
        }
        return "sub-langs=[\((codes + [".*-orig"]).joined(separator: ","))],write-auto-subs="
    }
}
