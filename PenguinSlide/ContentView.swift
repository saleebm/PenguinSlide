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
                    gearButton
                        .transition(.opacity)
                }
            }
            .overlay {
                settingsOverlay
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

    // MARK: - Pieces

    private var gearButton: some View {
        Button {
            openSettings()
        } label: {
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
        .opacity(showingSettings ? 0 : 1)
    }

    @ViewBuilder
    private var settingsOverlay: some View {
        if showingSettings {
            ZStack {
                Color.black.opacity(0.55)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { closeSettings() }
                    .transition(.opacity)

                SettingsView(onDismiss: closeSettings)
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

    // MARK: - Transitions

    private func openSettings() {
        withAnimation(overlaySpring) { showingSettings = true }
    }

    private func closeSettings() {
        withAnimation(overlaySpring) { showingSettings = false }
    }
}

#Preview {
    ContentView()
}
