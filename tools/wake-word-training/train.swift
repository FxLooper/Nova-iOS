#!/usr/bin/env swift
// Train Wake Word model using Create ML Sound Classifier
// Usage: swift train.swift

import Foundation
import CreateML

let trainingDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let heyNovaDir = trainingDir.appendingPathComponent("hey-nova")
let backgroundDir = trainingDir.appendingPathComponent("background")
let outputPath = trainingDir.appendingPathComponent("HeyNovaClassifier.mlmodel")

print("🎯 Training Hey Nova wake word classifier...")
print("   hey-nova samples: \(heyNovaDir.path)")
print("   background samples: \(backgroundDir.path)")

// Create ML expects folder structure: parent/className/files
// Move to proper structure
let dataDir = trainingDir.appendingPathComponent("training-data")
let heyNovaDest = dataDir.appendingPathComponent("hey_nova")
let bgDest = dataDir.appendingPathComponent("background")

try? FileManager.default.createDirectory(at: heyNovaDest, withIntermediateDirectories: true)
try? FileManager.default.createDirectory(at: bgDest, withIntermediateDirectories: true)

// Symlink files
let fm = FileManager.default
if let files = try? fm.contentsOfDirectory(atPath: heyNovaDir.path) {
    for f in files where f.hasSuffix(".wav") {
        let src = heyNovaDir.appendingPathComponent(f)
        let dst = heyNovaDest.appendingPathComponent(f)
        try? fm.removeItem(at: dst)
        try? fm.createSymbolicLink(at: dst, withDestinationURL: src)
    }
}
if let files = try? fm.contentsOfDirectory(atPath: backgroundDir.path) {
    for f in files where f.hasSuffix(".wav") {
        let src = backgroundDir.appendingPathComponent(f)
        let dst = bgDest.appendingPathComponent(f)
        try? fm.removeItem(at: dst)
        try? fm.createSymbolicLink(at: dst, withDestinationURL: src)
    }
}

print("📂 Training data prepared")

do {
    let data = try MLSoundClassifier.DataSource.labeledDirectories(at: dataDir)

    let params = MLSoundClassifier.ModelParameters(
        validation: .split(strategy: .automatic),
        maxIterations: 20
    )

    print("🏋️ Training...")
    let classifier = try MLSoundClassifier(trainingData: data, parameters: params)

    print("💾 Saving model to \(outputPath.path)")
    try classifier.write(to: outputPath)

    print("✅ Done! Model saved: HeyNovaClassifier.mlmodel")
    print("   Copy to Nova iOS project and integrate with SoundAnalysis")

} catch {
    print("❌ Training failed: \(error)")
}
