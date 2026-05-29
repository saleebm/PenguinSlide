//
//  GameOverView.swift
//  PenguinSlide
//
//  The end-of-round transition page. Presented by ContentView (over the
//  frozen scene) when GameScene fires onGameOver. Shows the final score,
//  the local top-5 board, a save-with-name action, a share button, and
//  "Play Again". Styled to match the SettingsView glass card so it reads as
//  part of the same icy world.
//

import SwiftUI

struct GameOverView: View {

    let result: GameResult
    /// Invoked by the "Play Again" button. ContentView dismisses the page
    /// and resumes the scene.
    let onPlayAgain: () -> Void

    /// Shield-ring blue from the game's palette — shared with SettingsView.
    private let accent = Color(red: 0.50, green: 0.90, blue: 1.00)

    @State private var name: String = PlayerProfile.name
    @State private var entries: [HighScore] = HighScores.entries
    /// The row this run wrote, once saved — used to highlight it and to flip
    /// the save control into its confirmed state. `nil` until the player saves.
    @State private var savedEntry: HighScore?
    @FocusState private var nameFieldFocused: Bool

    private var madeTheBoard: Bool { HighScores.qualifies(result.score) }
    private var shareText: String { "Penguin Slide — \(result.score) 🐧" }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 22) {
                    ScoreHeader(result: result, madeTheBoard: madeTheBoard, accent: accent)
                    LeaderboardSection(entries: entries,
                                       highlightID: savedEntry?.id,
                                       accent: accent)
                    SaveSection(accent: accent,
                                name: $name,
                                nameFieldFocused: $nameFieldFocused,
                                savedEntry: savedEntry,
                                onSave: save)
                }
                .padding(.horizontal, 22)
                .padding(.top, 24)
                .padding(.bottom, 20)
            }
            ActionBar(accent: accent, shareText: shareText, onPlayAgain: onPlayAgain)
                .padding(.horizontal, 22)
                .padding(.top, 6)
                .padding(.bottom, 20)
        }
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [accent.opacity(0.55), accent.opacity(0.15)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: .black.opacity(0.45), radius: 28, x: 0, y: 14)
        .padding(.horizontal, 20)
        .padding(.vertical, 40)
        .frame(maxWidth: 480, maxHeight: .infinity)
        .colorScheme(.dark)             // force light-on-dark legibility over the scrim
    }

    /// Commit the run to the board under the typed name (or "Anonymous"),
    /// remember the name for next time, and refresh the displayed list.
    private func save() {
        PlayerProfile.name = name
        let entry = HighScores.add(name: name, score: result.score, date: Date())
        entries = HighScores.entries
        // Only highlight/confirm if the run actually survived the trim.
        savedEntry = entries.contains(entry) ? entry : nil
        nameFieldFocused = false
    }
}

// MARK: - Sections

private struct ScoreHeader: View {
    let result: GameResult
    let madeTheBoard: Bool
    let accent: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: result.isNewBest ? "trophy.fill" : "snowflake")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(accent)
            Text(result.isNewBest ? "New Best!" : "Brrr!")
                .font(.system(.title, design: .rounded).weight(.heavy))
                .foregroundStyle(.white)
            Text("\(result.score)")
                .font(.system(size: 64, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .accessibilityLabel("Final score \(result.score)")
            if result.isNewBest {
                Badge(text: "Personal best", systemImage: "star.fill", accent: accent)
            } else if madeTheBoard {
                Badge(text: "You made the top 5", systemImage: "list.number", accent: accent)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct LeaderboardSection: View {
    let entries: [HighScore]
    let highlightID: HighScore.ID?
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Top Scores", accent: accent)
            if entries.isEmpty {
                Text("Be the first to make the board — save your run below.")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        if index > 0 {
                            Divider().overlay(Color.white.opacity(0.08))
                        }
                        ScoreRow(rank: index + 1,
                                 entry: entry,
                                 isHighlighted: entry.id == highlightID,
                                 accent: accent)
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                )
            }
        }
    }
}

private struct ScoreRow: View {
    let rank: Int
    let entry: HighScore
    let isHighlighted: Bool
    let accent: Color

    var body: some View {
        HStack(spacing: 12) {
            Text("\(rank)")
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundStyle(isHighlighted ? accent : .white.opacity(0.5))
                .frame(width: 22, alignment: .center)
            Text(entry.name)
                .font(.callout.weight(isHighlighted ? .bold : .regular))
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text("\(entry.score)")
                .font(.system(.callout, design: .rounded).weight(.bold))
                .monospacedDigit()
                .foregroundStyle(isHighlighted ? accent : .white.opacity(0.9))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(isHighlighted ? accent.opacity(0.12) : .clear)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Rank \(rank), \(entry.name), \(entry.score)")
    }
}

private struct SaveSection: View {
    let accent: Color
    @Binding var name: String
    var nameFieldFocused: FocusState<Bool>.Binding
    let savedEntry: HighScore?
    let onSave: () -> Void

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Save Your Score", accent: accent)
            if let savedEntry {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.title3)
                        .foregroundStyle(accent)
                    Text("Saved as \(savedEntry.name)")
                        .foregroundStyle(.white)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                )
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.title3)
                        .foregroundStyle(accent)
                    TextField("Your name", text: $name)
                        .textContentType(.name)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .focused(nameFieldFocused)
                        .onSubmit { if !trimmedName.isEmpty { onSave() } }
                        .foregroundStyle(.white)
                        .tint(accent)
                    Button(action: onSave) {
                        Text("Save")
                            .font(.callout.weight(.bold))
                            .foregroundStyle(trimmedName.isEmpty ? .white.opacity(0.4) : Color.black)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                Capsule().fill(trimmedName.isEmpty ? Color.white.opacity(0.12) : accent)
                            )
                    }
                    .disabled(trimmedName.isEmpty)
                    .accessibilityLabel("Save score")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                )
            }
        }
    }
}

private struct ActionBar: View {
    let accent: Color
    let shareText: String
    let onPlayAgain: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ShareLink(item: shareText) {
                Label("Share", systemImage: "square.and.arrow.up")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.white.opacity(0.12))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
                    )
            }
            .accessibilityLabel("Share score")

            Button(action: onPlayAgain) {
                Label("Play Again", systemImage: "arrow.clockwise")
                    .font(.callout.weight(.bold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(accent)
                    )
            }
            .accessibilityLabel("Play Again")
        }
    }
}

// MARK: - Building blocks

private struct SectionLabel: View {
    let text: String
    let accent: Color

    var body: some View {
        Text(text.uppercased())
            .font(.system(.caption, design: .rounded).weight(.heavy))
            .tracking(1.6)
            .foregroundStyle(accent.opacity(0.85))
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct Badge: View {
    let text: String
    let systemImage: String
    let accent: Color

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.system(.caption, design: .rounded).weight(.bold))
            .foregroundStyle(accent)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(accent.opacity(0.15)))
    }
}

#Preview("New best") {
    ZStack {
        LinearGradient(colors: [.blue, .black], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
        GameOverView(result: GameResult(score: 1240, isNewBest: true), onPlayAgain: {})
    }
}

#Preview("Regular run") {
    ZStack {
        LinearGradient(colors: [.blue, .black], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
        GameOverView(result: GameResult(score: 320, isNewBest: false), onPlayAgain: {})
    }
}
