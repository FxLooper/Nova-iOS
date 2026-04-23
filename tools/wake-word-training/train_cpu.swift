#!/usr/bin/env swift
import Foundation
import CreateML
import CoreML

let trainingDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let dataDir = trainingDir.appendingPathComponent("training-data")
let outputPath = trainingDir.appendingPathComponent("HeyNovaClassifier_CPU.mlmodel")

print("🎯 Training CPU-only Hey Nova classifier...")

do {
    let data = try MLSoundClassifier.DataSource.labeledDirectories(at: dataDir)
    let params = MLSoundClassifier.ModelParameters(
        validation: .split(strategy: .automatic),
        maxIterations: 20
    )
    let classifier = try MLSoundClassifier(trainingData: data, parameters: params)

    // Ulož model
    try classifier.write(to: outputPath)
    print("✅ Model saved: HeyNovaClassifier_CPU.mlmodel")
} catch {
    print("❌ Training failed: \(error)")
}
