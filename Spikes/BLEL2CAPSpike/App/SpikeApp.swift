//
//  SpikeApp.swift
//  BLEL2CAPSpike
//
//  SPIKE: drives the internal BLE L2CAP prototype between two devices and records timings.
//  Peripheral role echoes; central role measures. Launch arguments:
//    -role central|peripheral   start without tapping a button
//    -soak <seconds>            length of the 1 Hz ping phase used for background tests (default 120)
//  Results are written to Documents/ble-spike-<role>.json after every event.
//

import SwiftUI
import UIKit

@main
struct BLEL2CAPSpikeApp: App {
    @StateObject private var runner = SpikeRunner()

    var body: some Scene {
        WindowGroup {
            ContentView(runner: runner)
        }
    }
}

struct ContentView: View {
    @ObservedObject var runner: SpikeRunner

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("BLE L2CAP spike: \(runner.role ?? "idle")")
                .font(.headline)
            if runner.role == nil {
                HStack {
                    Button("Peripheral (echo)") { runner.start(role: "peripheral") }
                    Button("Central (measure)") { runner.start(role: "central") }
                }
                .buttonStyle(.borderedProminent)
            }
            ScrollView {
                Text(runner.logText)
                    .font(.system(size: 10, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
        .padding()
        .onAppear { runner.startFromLaunchArguments() }
    }
}
