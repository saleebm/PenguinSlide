//
//  PenguinSlideApp.swift
//  PenguinSlide
//
//  Tilt-controlled penguin dodging falling icicles.
//  Target: iOS 17+
//

import SwiftUI
import AVFoundation

@main
struct PenguinSlideApp: App {

    init() {
        // .playback + .mixWithOthers: game audio plays regardless of the
        // silent switch (standard game behaviour) while music apps and
        // podcasts keep playing underneath.
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, options: [.mixWithOthers])
        try? session.setActive(true)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .statusBarHidden(true)
                .persistentSystemOverlays(.hidden)
        }
    }
}
