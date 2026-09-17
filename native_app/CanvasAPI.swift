import Foundation

// 设置向导用的最小 Canvas API 客户端——只做"验证 token + 拉课程列表"这一件事，
// 直接用 URLSession，不用等 Python 那边的 requests，向导界面能更快响应。

struct CanvasCourse: Decodable {
    let id: Int
    let name: String?
    let courseCode: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case courseCode = "course_code"
    }

    var displayName: String {
        name ?? courseCode ?? "未命名课程 #\(id)"
    }
}

enum CanvasAPIError: LocalizedError {
    case badURL
    case unauthorized
    case httpError(Int)
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .badURL: return "网址格式不对，检查一下是不是漏了 https://"
        case .unauthorized: return "Token 无效或已过期"
        case .httpError(let code): return "请求失败（状态码 \(code)）"
        case .decodingFailed: return "服务器返回的内容解析不了，确认一下网址是不是 Canvas 的地址"
        }
    }
}

enum CanvasAPI {
    static func fetchCourses(baseURL: String, token: String, completion: @escaping (Result<[CanvasCourse], Error>) -> Void) {
        var trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasSuffix("/") { trimmed.removeLast() }
        if !trimmed.hasPrefix("http://") && !trimmed.hasPrefix("https://") {
            trimmed = "https://" + trimmed
        }

        guard var components = URLComponents(string: trimmed + "/api/v1/courses") else {
            completion(.failure(CanvasAPIError.badURL))
            return
        }
        components.queryItems = [
            URLQueryItem(name: "per_page", value: "50"),
            URLQueryItem(name: "enrollment_state", value: "active"),
        ]
        guard let url = components.url else {
            completion(.failure(CanvasAPIError.badURL))
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token.trimmingCharacters(in: .whitespacesAndNewlines))", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            guard let http = response as? HTTPURLResponse else {
                DispatchQueue.main.async { completion(.failure(CanvasAPIError.httpError(0))) }
                return
            }
            if http.statusCode == 401 {
                DispatchQueue.main.async { completion(.failure(CanvasAPIError.unauthorized)) }
                return
            }
            guard http.statusCode == 200, let data = data else {
                DispatchQueue.main.async { completion(.failure(CanvasAPIError.httpError(http.statusCode))) }
                return
            }
            do {
                let courses = try JSONDecoder().decode([CanvasCourse].self, from: data)
                DispatchQueue.main.async { completion(.success(courses)) }
            } catch {
                DispatchQueue.main.async { completion(.failure(CanvasAPIError.decodingFailed)) }
            }
        }.resume()
    }
}
