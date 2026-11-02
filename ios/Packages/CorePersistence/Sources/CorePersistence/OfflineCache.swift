// CorePersistence/Sources/CorePersistence/OfflineCache.swift
import Foundation

/// Простой офлайн-кэш Codable-снимков в Caches. Для связей «бронь ↔ событие календаря»
/// и сложных запросов в приложении используется SwiftData; этот кэш — для «последнего снимка» экранов.
public actor OfflineCache {
    public struct Entry<Value: Codable & Sendable>: Codable, Sendable {
        public let value: Value
        public let savedAt: Date
    }

    private let directory: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(directory: URL? = nil) {
        self.directory = directory
            ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("bitok-cache")
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    public func save<Value: Codable & Sendable>(_ value: Value, forKey key: String, now: Date = Date()) throws {
        let data = try encoder.encode(Entry(value: value, savedAt: now))
        try data.write(to: url(for: key), options: .atomic)
    }

    /// Возвращает снимок и время сохранения — для подписи «Обновлено <дата>» в офлайне (AC-012.3).
    public func load<Value: Codable & Sendable>(_ type: Value.Type, forKey key: String) -> Entry<Value>? {
        guard let data = try? Data(contentsOf: url(for: key)) else { return nil }
        return try? decoder.decode(Entry<Value>.self, from: data)
    }

    private func url(for key: String) -> URL {
        directory.appendingPathComponent(key.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? key)
    }
}
