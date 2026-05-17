//
//  ContentView.swift
//  PenguinSlide
//

import SwiftUI
import SpriteKit

struct ContentView: View {

    // GeometryReader lets the scene size itself to the device. We build the
    // scene once with @State so SwiftUI redraws don't recreate it — that was
    // a known footgun on early iOS 15 betas and is still the right pattern.
    @State private var scene: GameScene?
    @State private var showingSettings = false

    private let overlaySpring = Animation.spring(response: 0.38, dampingFraction: 0.82)

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let scene {
                    SpriteView(
                        scene: scene,
                        // Render debug overlays off; transparent off so the
                        // sky gradient inside the scene is what you see.
                        options: [.shouldCullNonVisibleNodes]
                    )
                    .ignoresSafeArea()
                } else {
                    // First-frame placeholder while we size the scene.
                    Color(red: 0.72, green: 0.88, blue: 0.96)
                        .ignoresSafeArea()
                }
            }
            .overlay(alignment: .topTrailing) {
                if scene != nil {
                    GearButton(isHidden: showingSettings, action: openSettings)
                        .transition(.opacity)
                }
            }
            .overlay {
                SettingsOverlay(isPresented: showingSettings, onDismiss: closeSettings)
            }
            .onAppear {
                if scene == nil {
                    let s = GameScene(size: proxy.size)
                    s.scaleMode = .resizeFill
                    withAnimation(overlaySpring) { scene = s }
                }
            }
            // Pause/resume so the round freezes while settings is up; the
            // dt sentinel inside resumeFromSettings keeps the first frame
            // after dismiss from teleporting the penguin.
            .onChange(of: showingSettings) { _, isShowing in
                if isShowing {
                    scene?.pauseForSettings()
                } else {
                    scene?.resumeFromSettings()
                }
            }
        }
    }

    // MARK: - Transitions

    private func openSettings() {
        withAnimation(overlaySpring) { showingSettings = true }
    }

    private func closeSettings() {
        withAnimation(overlaySpring) { showingSettings = false }
    }
}

// MARK: - Pieces

private struct GearButton: View {
    let isHidden: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "gearshape.fill")
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white)
                .padding(11)
                .background(.black.opacity(0.40), in: Circle())
                .overlay(
                    Circle().strokeBorder(.white.opacity(0.18), lineWidth: 1)
                )
        }
        .padding(.top, 12)
        .padding(.trailing, 16)
        .accessibilityLabel("Settings")
        // Hide the gear while the modal is up so it doesn't poke through
        // the scrim during the dismiss animation.
        .opacity(isHidden ? 0 : 1)
    }
}

private struct SettingsOverlay: View {
    let isPresented: Bool
    let onDismiss: () -> Void

    var body: some View {
        if isPresented {
            ZStack {
                // Scrim is a Button (not onTapGesture) so VoiceOver, Switch
                // Control, and visionOS eye tracking treat the dismiss zone
                // as an actuator instead of skipping it.
                Button(action: onDismiss) {
                    Color.black.opacity(0.55)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .transition(.opacity)
                .accessibilityLabel("Dismiss settings")
                .accessibilityAddTraits(.isButton)

                SettingsView(onDismiss: onDismiss)
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
            }
            // Keep the card anchored when the keyboard appears — without
            // this SwiftUI insets the bottom safe area and the card gets
            // squashed/pushed upward as the keyboard slides in. The name
            // field is at the top of the card so it stays visible above
            // the keyboard.
            .ignoresSafeArea(.keyboard, edges: .bottom)
        }
    }
}

#Preview {
    ContentView()
}
