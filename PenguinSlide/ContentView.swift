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
            .onAppear {
                if scene == nil {
                    let s = GameScene(size: proxy.size)
                    s.scaleMode = .resizeFill
                    scene = s
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
