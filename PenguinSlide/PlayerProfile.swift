//
//  PlayerProfile.swift
//  PenguinSlide
//
//  Isolated UserDefaults wrapper for the player's identity. Kept separate
//  from `PenguinTuning` so future profile fields (avatar, color) don't
//  bloat the difficulty struct.
//

import Foundation

enum PlayerProfile {

    private static let nameKey = "playerName"

    /// Player's display name. Empty string when unset. Whitespace is
    /// trimmed on write so a stray space doesn't read as a real name.
    static var name: String {
        get { UserDefaults.standard.string(forKey: nameKey) ?? "" }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            UserDefaults.standard.set(trimmed, forKey: nameKey)
        }
    }
}
