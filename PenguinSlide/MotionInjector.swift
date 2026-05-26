//
//  MotionInjector.swift
//  PenguinSlide
//
//  DEBUG-only, simulator-only tilt feed. The simulator can't deliver
//  CoreMotion data and `xcrun simctl` has no `motion` subcommand, so
//  this listener gives us a way to drive tilt from a host-side script
//  (see scripts/inject-tilt.sh) without depending on the keyboard
//  fallback in GameScene.currentTilt().
//
//  Pattern is inspired by sammyd/accelesender and the WebSocket-bridge
//  approach described by Jaskirat Singh; kept minimal — Network.framework
//  TCP listener accepting newline-delimited JSON frames of the form
//  {"gravity_y": 0.42} so we add no external dependencies.
//

#if DEBUG && targetEnvironment(simulator)

import CoreGraphics
import Foundation
import Network

final class MotionInjector {

    static let shared = MotionInjector()

    /// Most recent injected sample, with the time it arrived. GameScene
    /// reads this and ignores samples older than ~500 ms so a stale
    /// value can't pin the penguin if the injector is disconnected.
    private(set) var latestTilt: (value: CGFloat, at: Date)?

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "MotionInjector.listener")
    private var started = false

    /// Idempotent — safe to call from didFinishLaunchingWithOptions and
    /// from `GameScene.didMove(to:)` without double-binding the port.
    func start(port: NWEndpoint.Port = 7654) {
        guard !started else { return }
        started = true
        do {
            let l = try NWListener(using: .tcp, on: port)
            l.newConnectionHandler = { [weak self] conn in self?.accept(conn) }
            l.start(queue: queue)
            listener = l
            NSLog("[MotionInjector] listening on 127.0.0.1:\(port.rawValue)")
        } catch {
            NSLog("[MotionInjector] failed to bind: \(error)")
            started = false
        }
    }

    private func accept(_ conn: NWConnection) {
        conn.start(queue: queue)
        receive(on: conn, buffer: Data())
    }

    private func receive(on conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buf = buffer
            if let data, !data.isEmpty { buf.append(data) }

            // Frames are newline-delimited so a slow writer (or netcat)
            // can stream multiple samples on one connection.
            while let nl = buf.firstIndex(of: 0x0A) {
                let line = buf.subdata(in: buf.startIndex..<nl)
                buf.removeSubrange(buf.startIndex...nl)
                self.parse(line)
            }

            if isComplete || error != nil {
                conn.cancel()
                return
            }
            self.receive(on: conn, buffer: buf)
        }
    }

    private func parse(_ line: Data) {
        struct Frame: Decodable { let gravity_y: Double }
        guard let frame = try? JSONDecoder().decode(Frame.self, from: line) else { return }
        latestTilt = (CGFloat(frame.gravity_y), Date())
    }
}

#endif
