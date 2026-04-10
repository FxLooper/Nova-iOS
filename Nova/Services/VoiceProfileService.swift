import Foundation
import AVFoundation

// MARK: - VoiceProfileService
// Nova Voice ID — speaker verification using SpeechBrain ECAPA-TDNN on Mac server.
//
// Flow:
//   1. Enrollment: record 3×10s samples → upload to Mac → average embeddings → store in Keychain
//   2. Verification: send short audio chunk → Mac extracts embedding → cosine similarity → accept/reject
//
// Storage: Keychain (encrypted, per-app sandbox)
// Format: 192-dim L2-normalized Float32 vector
// Threshold: 0.75 soft / 0.85 strict

@MainActor
class VoiceProfileService: ObservableObject {

    enum ProfileState: Equatable {
        case notEnrolled
        case enrolling(step: Int, totalSteps: Int)
        case uploading
        case processing
        case enrolled
        case error(String)
    }

    @Published private(set) var state: ProfileState = .notEnrolled
    @Published private(set) var enrollmentSamplesCount: Int = 0
    @Published var verificationConfidence: Float = 0.0
    @Published var lastVerificationResult: Bool = false

    // Verification thresholds (L2-normalized cosine similarity)
    let softThreshold: Float = 0.75   // casual chat
    let strictThreshold: Float = 0.85  // dev mode, payments

    private let keychainKey = "nova_voice_profile_embedding"
    private var serverURL: String = ""
    private var token: String = ""

    // Temp storage for enrollment samples
    private var enrollmentSampleURLs: [URL] = []

    init() {
        updateStateFromStorage()
    }

    func configure(serverURL: String, token: String) {
        self.serverURL = serverURL
        self.token = token
    }

    // MARK: - Storage

    private func updateStateFromStorage() {
        if loadEnrolledEmbedding() != nil {
            state = .enrolled
        } else {
            state = .notEnrolled
        }
    }

    private func saveEnrolledEmbedding(_ embedding: [Float]) {
        // Convert to Data (Float32 array → raw bytes)
        let data = embedding.withUnsafeBufferPointer { Data(buffer: $0) }
        KeychainHelper.save(key: keychainKey, value: data.base64EncodedString())
    }

    private func loadEnrolledEmbedding() -> [Float]? {
        guard let base64 = KeychainHelper.load(key: keychainKey),
              let data = Data(base64Encoded: base64) else { return nil }

        let count = data.count / MemoryLayout<Float>.size
        let embedding = data.withUnsafeBytes { ptr -> [Float] in
            let buf = ptr.bindMemory(to: Float.self)
            return Array(buf.prefix(count))
        }
        return embedding
    }

    func deleteProfile() {
        KeychainHelper.delete(key: keychainKey)
        enrollmentSampleURLs.removeAll()
        state = .notEnrolled
    }

    // MARK: - Enrollment Flow

    /// Start the enrollment flow. Call `recordNextSample()` for each step.
    func startEnrollment() {
        enrollmentSampleURLs.removeAll()
        enrollmentSamplesCount = 0
        state = .enrolling(step: 1, totalSteps: 3)
    }

    /// Called by the UI after the user records one sample.
    /// - Parameter audioFileURL: Local temp file with recorded audio (WAV/M4A).
    func addEnrollmentSample(_ audioFileURL: URL) async {
        enrollmentSampleURLs.append(audioFileURL)
        enrollmentSamplesCount = enrollmentSampleURLs.count

        if enrollmentSamplesCount < 3 {
            state = .enrolling(step: enrollmentSamplesCount + 1, totalSteps: 3)
        } else {
            // All samples collected — process them
            await finalizeEnrollment()
        }
    }

    private func finalizeEnrollment() async {
        state = .uploading

        do {
            var embeddings: [[Float]] = []
            for url in enrollmentSampleURLs {
                let embedding = try await extractEmbedding(audioFileURL: url)
                embeddings.append(embedding)
            }

            state = .processing

            // Average the embeddings (centroid)
            guard !embeddings.isEmpty else {
                state = .error("No samples to process")
                return
            }

            let dim = embeddings[0].count
            var averaged = [Float](repeating: 0, count: dim)
            for emb in embeddings {
                for i in 0..<dim {
                    averaged[i] += emb[i]
                }
            }
            for i in 0..<dim {
                averaged[i] /= Float(embeddings.count)
            }

            // L2-normalize the average
            let norm = sqrt(averaged.reduce(0) { $0 + $1 * $1 })
            if norm > 0 {
                for i in 0..<dim {
                    averaged[i] /= norm
                }
            }

            saveEnrolledEmbedding(averaged)
            print("[voice-id] ✅ enrolled with \(embeddings.count) samples, \(dim)-dim averaged embedding")

            // Cleanup temp files
            for url in enrollmentSampleURLs {
                try? FileManager.default.removeItem(at: url)
            }
            enrollmentSampleURLs.removeAll()

            state = .enrolled
            HapticManager.shared.voiceEnrollmentSuccess()
        } catch {
            state = .error("Enrollment failed: \(error.localizedDescription)")
            print("[voice-id] enrollment error: \(error)")
            HapticManager.shared.voiceEnrollmentFailed()
        }
    }

    // MARK: - Verification

    /// Verify that the given audio was spoken by the enrolled user.
    /// - Returns: (verified: Bool, confidence: Float) where confidence is cosine similarity [0, 1]
    func verify(audioFileURL: URL, strict: Bool = false) async -> (verified: Bool, confidence: Float) {
        guard let profile = loadEnrolledEmbedding() else {
            return (false, 0.0)
        }

        do {
            let embedding = try await extractEmbedding(audioFileURL: audioFileURL)
            let similarity = cosineSimilarity(profile, embedding)
            let threshold = strict ? strictThreshold : softThreshold
            let verified = similarity >= threshold

            await MainActor.run {
                self.verificationConfidence = similarity
                self.lastVerificationResult = verified
            }

            print("[voice-id] verify: similarity=\(String(format: "%.3f", similarity)) threshold=\(threshold) → \(verified ? "✅ match" : "❌ no match")")
            return (verified, similarity)
        } catch {
            print("[voice-id] verify error: \(error)")
            return (false, 0.0)
        }
    }

    // MARK: - Mac server embedding extraction

    private func extractEmbedding(audioFileURL: URL) async throws -> [Float] {
        guard !serverURL.isEmpty else {
            throw NSError(domain: "VoiceProfileService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Server not configured"])
        }

        guard let url = URL(string: "\(serverURL)/api/voice/embed") else {
            throw NSError(domain: "VoiceProfileService", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid server URL"])
        }

        let audioData = try Data(contentsOf: audioFileURL)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue(token, forHTTPHeaderField: "X-Nova-Token")
        request.httpBody = audioData
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "VoiceProfileService", code: -3, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }

        guard httpResponse.statusCode == 200 else {
            let errorMsg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String ?? "HTTP \(httpResponse.statusCode)"
            throw NSError(domain: "VoiceProfileService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMsg])
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let embedding = json["embedding"] as? [Double] else {
            throw NSError(domain: "VoiceProfileService", code: -4, userInfo: [NSLocalizedDescriptionKey: "Invalid embedding response"])
        }

        return embedding.map { Float($0) }
    }

    // MARK: - Cosine Similarity (assumes L2-normalized inputs)

    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return 0 }
        var dot: Float = 0
        for i in 0..<a.count {
            dot += a[i] * b[i]
        }
        return dot // For L2-normalized vectors, dot product = cosine similarity
    }
}
