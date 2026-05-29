//
//  HighScores.swift
//  PenguinSlide
//
//  Local, on-device leaderboard. A JSON-encoded list of named runs in
//  UserDefaults — fully offline, no accounts. Kept separate from the
//  auto-tracked `best_score` (which GameScene writes every round): the
//  leaderboard only gains an entry when the player deliberately saves a
//  run with a name on the game-over page.
//

import Foundation

/// One saved run on the local leaderboard.
struct HighScore: Codable, Identifiable, Equatable {
    let id: UUID
    let name: String
    let score: Int
    let date: Date

    init(id: UUID = UUID(), name: String, score: Int, date: Date) {
        self.id = id
        self.name = name
        self.score = score
        self.date = date
    }
}

enum HighScores {

    /// How many runs the board keeps. The game-over page shows all of them.
    static let capacity = 5

    private static let key = "highScores"

    /// The board, already sorted best-first. Returns `[]` on first run or if
    /// the stored blob ever fails to decode (treat a corrupt board as empty
    /// rather than crashing the game-over page).
    static var entries: [HighScore] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([HighScore].self, from: data) else {
            return []
        }
        return decoded
    }

    /// Whether `score` would earn a spot on the board — true while there's an
    /// open slot, or once it beats the current lowest entry. Drives the
    /// "you made the board" framing on the game-over page. A zero score never
    /// qualifies (an instant wipe shouldn't claim a slot).
    static func qualifies(_ score: Int) -> Bool {
        guard score > 0 else { return false }
        let current = entries
        if current.count < capacity { return true }
        return score > (current.last?.score ?? 0)
    }

    /// Insert a run, re-sort, trim to `capacity`, and persist. Returns the
    /// stored entry so the caller can highlight the freshly added row (the
    /// returned `id` survives trimming only if the run actually made the cut).
    @discardableResult
    static func add(name: String, score: Int, date: Date) -> HighScore {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let entry = HighScore(name: trimmedName.isEmpty ? "Anonymous" : trimmedName,
                              score: score,
                              date: date)
        var list = entries
        list.append(entry)
        // Higher score first; ties broken by who got there first so an earlier
        // run isn't bumped by a later identical one.
        list.sort { $0.score != $1.score ? $0.score > $1.score : $0.date < $1.date }
        if list.count > capacity { list = Array(list.prefix(capacity)) }
        persist(list)
        return entry
    }

    private static func persist(_ list: [HighScore]) {
        guard let data = try? JSONEncoder().encode(list) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
