//
//  SettingsView.swift
//  PenguinSlide
//
//  Glass-card overlay shown by ContentView's gear button. Not a native
//  sheet: we render this inside a ZStack so we control the entry/exit
//  animation and the surrounding scrim to match the game's icy theme.
//

import SwiftUI

struct SettingsView: View {

    /// Closure the close button (and ContentView's scrim tap) invoke. The
    /// view doesn't own its own presentation state — keeps the dismiss
    /// path single-sourced through ContentView.
    let onDismiss: () -> Void

    @State private var name: String = PlayerProfile.name

    /// Shield-ring blue from the game's existing palette. Used as the
    /// accent so the modal reads as part of the same world.
    private let accent = Color(red: 0.50, green: 0.90, blue: 1.00)

    var body: some View {
        VStack(spacing: 0) {
            SettingsHeader(accent: accent, name: $name, onDismiss: onDismiss)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    PlayerSection(accent: accent, name: $name)
                    GameplaySection(accent: accent)
                    HowToPlaySection(accent: accent)
                    AboutSection(accent: accent)
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 24)
            }
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
        .frame(maxWidth: 480)
        .colorScheme(.dark)             // force light-on-dark legibility over the scrim
        // Commit the typed name no matter how the modal goes away (X
        // button, scrim tap, or background dismiss). Without this, a
        // scrim-tap dismiss would silently drop the in-flight edit.
        .onDisappear { PlayerProfile.name = name }
    }
}

// MARK: - Sections

private struct SettingsHeader: View {
    let accent: Color
    @Binding var name: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "snowflake")
                .font(.title3.weight(.semibold))
                .foregroundStyle(accent)
            Text("Settings")
                .font(.system(.title2, design: .rounded).weight(.bold))
                .foregroundStyle(.white)
            Spacer()
            Button {
                PlayerProfile.name = name
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white.opacity(0.85))
            }
            .accessibilityLabel("Close settings")
        }
        .padding(.horizontal, 22)
        .padding(.top, 20)
        .padding(.bottom, 14)
    }
}

private struct PlayerSection: View {
    let accent: Color
    @Binding var name: String
    @FocusState private var nameFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Player", accent: accent)
            HStack(spacing: 12) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.title3)
                    .foregroundStyle(accent)
                TextField("Your name", text: $name)
                    // .name enables the QuickType "use my contact name"
                    // suggestion above the keyboard.
                    .textContentType(.name)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled(false)
                    .submitLabel(.done)
                    .focused($nameFieldFocused)
                    .onSubmit {
                        PlayerProfile.name = name
                        nameFieldFocused = false
                    }
                    .foregroundStyle(.white)
                    .tint(accent)
                if !name.isEmpty {
                    Button {
                        name = ""
                        nameFieldFocused = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.white.opacity(0.45))
                    }
                    .accessibilityLabel("Clear name")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
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

private struct GameplaySection: View {
    let accent: Color
    // Seeded from the persisted tuning so the slider opens on whatever
    // the player last chose, not the default.
    @State private var speed: Double = Double(Tuning.Penguin.maxSpeed)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel(text: "Gameplay", accent: accent)
                Spacer()
                Button("Reset") {
                    speed = Double(PenguinTuning.speedDefault)
                    persist(speed)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(accent)
                .accessibilityLabel("Reset penguin speed to default")
            }
            HStack(spacing: 12) {
                Image(systemName: "hare.fill")
                    .font(.title3)
                    .foregroundStyle(accent)
                    .frame(width: 22, alignment: .center)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Penguin Speed")
                            .foregroundStyle(.white)
                        Spacer()
                        Text("\(Int(speed))")
                            .monospacedDigit()
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    Slider(
                        value: $speed,
                        in: Double(PenguinTuning.speedRange.lowerBound)...Double(PenguinTuning.speedRange.upperBound),
                        step: 10
                    ) { editing in
                        // Commit on release so a drag doesn't thrash
                        // UserDefaults on every intermediate value.
                        if !editing { persist(speed) }
                    }
                    .tint(accent)
                    .accessibilityValue(Text("\(Int(speed)) points per second"))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
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

    // Penguin reads `Tuning.Penguin.maxSpeed` every frame, so this
    // takes effect live in any active game without a scene reload.
    private func persist(_ value: Double) {
        Tuning.Penguin.maxSpeed = CGFloat(value)
        Tuning.Penguin.saveToUserDefaults()
    }
}

private struct HowToPlaySection: View {
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel(text: "How to Play", accent: accent)
            TipRow(accent: accent,
                   systemImage: "iphone.gen3.radiowaves.left.and.right",
                   text: "Tilt your phone left and right to slide on the ice.")
            TipRow(accent: accent,
                   systemImage: "snowflake",
                   text: "Dodge falling icicles — three hits and the round ends.")
            TipRow(accent: accent,
                   systemImage: "trophy.fill",
                   text: "Survive longer to grow your score and beat your best.")
        }
    }
}

private struct AboutSection: View {
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "About", accent: accent)
            HStack {
                Text("Version")
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                Text(Bundle.main.shortVersion)
                    .foregroundStyle(.white.opacity(0.95))
                    .monospacedDigit()
            }
            .font(.subheadline)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
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
    }
}

private struct TipRow: View {
    let accent: Color
    let systemImage: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: systemImage)
                .font(.callout)
                .foregroundStyle(accent)
                .frame(width: 22, alignment: .center)
            Text(text)
                .font(.callout)
                .foregroundStyle(.white.opacity(0.92))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private extension Bundle {
    var shortVersion: String {
        (infoDictionary?["CFBundleShortVersionString"] as? String) ?? "—"
    }
}

#Preview {
    ZStack {
        LinearGradient(colors: [.blue, .black], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
        SettingsView(onDismiss: {})
    }
}
