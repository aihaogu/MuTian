import Foundation

struct MetadataCandidate {
    var title: String?
    var author: String?
    var sourceName: String?
    var sourceURL: String?
}

enum MetadataParser {
    static func parseMetadata(in directory: URL) -> MetadataCandidate {
        let candidates = ["metadata.json", "manifest.json", "info.json"]
        for fileName in candidates {
            let url = directory.appendingPathComponent(fileName)
            guard let data = try? Data(contentsOf: url),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            let title = firstString(object, keys: ["title", "label", "name", "dc:title"])
            let author = firstString(object, keys: ["author", "creator", "dc:creator"])
            let source = firstString(object, keys: ["attribution", "provider", "source", "repository"])
            let sourceURL = firstString(object, keys: ["@id", "id", "url", "homepage"])
            return MetadataCandidate(title: title, author: author, sourceName: source, sourceURL: sourceURL)
        }
        return MetadataCandidate(title: nil, author: nil, sourceName: nil, sourceURL: nil)
    }

    private static func firstString(_ object: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = object[key] as? String, !value.isEmpty {
                return value
            }
            if let value = object[key] as? [String: Any] {
                if let nested = value["@value"] as? String {
                    return nested
                }
                if let nested = value["value"] as? String {
                    return nested
                }
            }
            if let value = object[key] as? [[String: Any]],
               let first = value.first {
                if let nested = first["@value"] as? String {
                    return nested
                }
                if let nested = first["value"] as? String {
                    return nested
                }
                if let nested = first["label"] as? String {
                    return nested
                }
            }
        }
        return nil
    }
}
