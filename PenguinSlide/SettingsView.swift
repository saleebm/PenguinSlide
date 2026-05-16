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
    @FocusState private var nameFieldFocused: Bool

    /// Shield-ring blue from the game's existing palette. Used as the
    /// accent so the modal reads as part of the same world.
    private let accent = Color(red: 0.50, green: 0.90, blue: 1.00)

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    playerSection
                    howToPlaySection
                    aboutSection
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

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "snowflake")
                .font(.title3.weight(.semibold))
                .foregroundStyle(accent)
            Text("Settings")
                .font(.system(.title2, design: .rounded, weight: .bold))
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

    // MARK: - Sections

    private var playerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Player")
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

    private var howToPlaySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("How to Play")
            tipRow(systemImage: "iphone.gen3.radiowaves.left.and.right",
                   text: "Tilt your phone left and right to slide on the ice.")
            tipRow(systemImage: "snowflake",
                   text: "Dodge falling icicles — three hits and the round ends.")
            tipRow(systemImage: "trophy.fill",
                   text: "Survive longer to grow your score and beat your best.")
        }
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("About")
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

    // MARK: - Building blocks

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(.caption, design: .rounded, weight: .heavy))
            .tracking(1.6)
            .foregroundStyle(accent.opacity(0.85))
    }

    private func tipRow(systemImage: String, text: String) -> some View {
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
