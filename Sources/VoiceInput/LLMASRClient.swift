import Foundation
import os.log

private let logger = Logger(subsystem: "com.yetone.VoiceInput", category: "LLMASRClient")

final class LLMASRClient {
    static let shared = LLMASRClient()

    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "asrEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "asrEnabled") }
    }

    var apiBaseURL: String {
        get { UserDefaults.standard.string(forKey: "asrAPIBaseURL") ?? "https://openrouter.ai/api/v1" }
        set { UserDefaults.standard.set(newValue, forKey: "asrAPIBaseURL") }
    }

    var apiKey: String {
        get { UserDefaults.standard.string(forKey: "asrAPIKey") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "asrAPIKey") }
    }

    var model: String {
        get { UserDefaults.standard.string(forKey: "asrModel") ?? "openai/whisper-large-v3-turbo" }
        set { UserDefaults.standard.set(newValue, forKey: "asrModel") }
    }

    var language: String {
        get { UserDefaults.standard.string(forKey: "asrLanguage") ?? "zh" }
        set { UserDefaults.standard.set(newValue, forKey: "asrLanguage") }
    }

    var isConfigured: Bool {
        let url = apiBaseURL.lowercased()
        let isLocal = url.contains("localhost") || url.contains("127.0.0.1")
        return isLocal || !apiKey.isEmpty
    }

    func transcribe(
        audioData: Data,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let baseURL = apiBaseURL.hasSuffix("/") ? String(apiBaseURL.dropLast()) : apiBaseURL
        let useOpenRouterFormat = baseURL.lowercased().contains("openrouter")

        guard let url = URL(string: "\(baseURL)/audio/transcriptions") else {
            completion(.failure(ASRError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30

        if useOpenRouterFormat {
            // OpenRouter: JSON + base64 格式
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let base64Audio = audioData.base64EncodedString()
            let body: [String: Any] = [
                "model": model,
                "input_audio": [
                    "data": base64Audio,
                    "format": "wav"
                ]
            ]
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        } else {
            // 标准 OpenAI multipart 格式
            let boundary = "Boundary-\(UUID().uuidString)"
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

            var body = Data()
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
            body.append(audioData)
            body.append("\r\n".data(using: .utf8)!)

            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(model)\r\n".data(using: .utf8)!)

            if !language.isEmpty {
                body.append("--\(boundary)\r\n".data(using: .utf8)!)
                body.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n".data(using: .utf8)!)
                body.append("\(language)\r\n".data(using: .utf8)!)
            }

            body.append("--\(boundary)--\r\n".data(using: .utf8)!)
            request.httpBody = body
        }

        logger.info("ASR request: \(url.absoluteString) model=\(self.model)")

        let task = URLSession.shared.dataTask(with: request) { data, _, error in
            if let error {
                logger.error("ASR error: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }
            guard let data else {
                completion(.failure(ASRError.noData))
                return
            }

            // 尝试解析 OpenAI 格式 {"text": "..."}
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let text = json["text"] as? String {
                logger.info("ASR result: \(text)")
                completion(.success(text))
                return
            }

            // fallback: 尝试直接当纯文本返回
            if let text = String(data: data, encoding: .utf8), !text.isEmpty {
                completion(.success(text))
                return
            }

            completion(.failure(ASRError.invalidResponse))
        }
        task.resume()
    }

    enum ASRError: LocalizedError {
        case invalidURL
        case noData
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Invalid ASR API URL"
            case .noData: return "No data returned from ASR"
            case .invalidResponse: return "Invalid ASR response format"
            }
        }
    }
}
