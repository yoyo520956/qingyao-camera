import Foundation
import UIKit

final class AgnesClient {

    static let shared = AgnesClient()
    private init() {}

    static let defaultKey = "sk-XaGjXJS77FniRVmacdbsfUwf1OR4wtUxTSNtCFg4cV1HeS82"

    var baseURL: String {
        UserDefaults.standard.string(forKey: "agnes_base_url") ?? "https://api.agnes-ai.cn"
    }

    var apiKey: String {
        UserDefaults.standard.string(forKey: "agnes_api_key") ?? Self.defaultKey
    }

    enum Quality: String {
        case ultra2K = "超清 2K"
        case fast = "快速"
    }

    static func outputSize(for image: UIImage, quality: Quality) -> String {
        let isLandscape = image.size.width >= image.size.height
        switch quality {
        case .ultra2K:
            if abs(image.size.width - image.size.height) < 1 {
                return "2048x2048"
            }
            return isLandscape ? "2731x2048" : "2048x2731"
        case .fast:
            return isLandscape ? "1024x768" : "1024x1536"
        }
    }

    enum AgnesError: LocalizedError {
        case compressionFailed
        case http(Int, String)
        case badResponse
        case noImage
        case downloadFailed

        var errorDescription: String? {
            switch self {
            case .compressionFailed: return "图片压缩失败"
            case .http(let code, let msg):
                if code == 429 { return "服务器繁忙（限流），请稍等约 1 分钟再试" }
                return "请求失败（\(code)）：\(msg)"
            case .badResponse: return "服务返回格式异常"
            case .noImage: return "服务未返回图像"
            case .downloadFailed: return "结果下载失败"
            }
        }
    }

    func editImage(inputs: [UIImage],
                   prompt: String,
                   quality: Quality,
                   completion: @escaping (Result<UIImage, Error>) -> Void) {
        guard let first = inputs.first else {
            DispatchQueue.main.async { completion(.failure(AgnesError.noImage)) }
            return
        }

        var dataURIs: [String] = []
        for img in inputs {
            guard let jpeg = img.agnesCompressed(maxDimension: 2048, quality: 0.9) else {
                DispatchQueue.main.async { completion(.failure(AgnesError.compressionFailed)) }
                return
            }
            dataURIs.append("data:image/jpeg;base64," + jpeg.base64EncodedString())
        }

        let body: [String: Any] = [
            "model": "agnes-image-2.5-flash",
            "prompt": prompt,
            "size": Self.outputSize(for: first, quality: quality),
            "extra_body": [
                "image": dataURIs,
                "response_format": "url"
            ]
        ]

        send(body: body, attempt: 0, completion: completion)
    }

    private func send(body: [String: Any],
                      attempt: Int,
                      completion: @escaping (Result<UIImage, Error>) -> Void) {
        guard let url = URL(string: baseURL + "/v1/images/generations") else {
            DispatchQueue.main.async { completion(.failure(AgnesError.badResponse)) }
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer " + apiKey, forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 360
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }

            if let http = response as? HTTPURLResponse, http.statusCode == 429, attempt < 2 {
                DispatchQueue.global().asyncAfter(deadline: .now() + 25) {
                    self.send(body: body, attempt: attempt + 1, completion: completion)
                }
                return
            }

            if let error = error {
                DispatchQueue.main.async {
                    completion(.failure(AgnesError.http(-1, error.localizedDescription)))
                }
                return
            }

            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                DispatchQueue.main.async { completion(.failure(AgnesError.badResponse)) }
                return
            }

            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                let msg = String(data: data, encoding: .utf8)?.prefix(200) ?? ""
                DispatchQueue.main.async {
                    completion(.failure(AgnesError.http(http.statusCode, String(msg))))
                }
                return
            }

            guard let arr = json["data"] as? [[String: Any]], let first = arr.first else {
                DispatchQueue.main.async { completion(.failure(AgnesError.noImage)) }
                return
            }

            if let urlStr = first["url"] as? String, let resultURL = URL(string: urlStr) {
                self.download(resultURL, completion: completion)
            } else if let b64 = first["b64_json"] as? String,
                      let imgData = Data(base64Encoded: b64),
                      let image = UIImage(data: imgData) {
                DispatchQueue.main.async { completion(.success(image)) }
            } else {
                DispatchQueue.main.async { completion(.failure(AgnesError.noImage)) }
            }
        }.resume()
    }

    private func download(_ url: URL, completion: @escaping (Result<UIImage, Error>) -> Void) {
        URLSession.shared.dataTask(with: url) { data, _, error in
            if let data = data, let image = UIImage(data: data) {
                DispatchQueue.main.async { completion(.success(image)) }
            } else {
                DispatchQueue.main.async {
                    completion(.failure(AgnesError.downloadFailed))
                }
            }
        }.resume()
    }
}

extension UIImage {

    func agnesCompressed(maxDimension: CGFloat, quality: CGFloat) -> Data? {
        let maxSide = max(size.width, size.height)
        guard maxSide > 0 else { return nil }
        let scale = min(1.0, maxDimension / maxSide)
        let newSize = CGSize(width: max(1, size.width * scale),
                             height: max(1, size.height * scale))
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resized = renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
        return resized.jpegData(compressionQuality: quality)
    }

    func cropped(toRatio ratio: CGFloat) -> UIImage {
        guard let cg = self.cgImage else { return self }
        let w = CGFloat(cg.width)
        let h = CGFloat(cg.height)
        let current = w / h
        if abs(current - ratio) < 0.015 { return self }
        var rect: CGRect
        if current > ratio {
            let newW = h * ratio
            rect = CGRect(x: (w - newW) / 2, y: 0, width: newW, height: h)
        } else {
            let newH = w / ratio
            rect = CGRect(x: 0, y: (h - newH) / 2, width: w, height: newH)
        }
        guard let croppedCG = cg.cropping(to: rect) else { return self }
        return UIImage(cgImage: croppedCG, scale: self.scale, orientation: self.imageOrientation)
    }
}
