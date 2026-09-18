import Cocoa
import WebKit

// 网页 <-> 原生代码的桥接层：设置向导 (setup_wizard.html)、设置面板 (settings.html)、
// 提醒时间 (schedule.html) 都是普通网页，通过这层桥接调用原生能力（读写配置文件、
// 跑 Python 脚本、开关窗口）。JS 那边用 bridge.js 里的 NativeBridge.send(action, payload)
// 发消息，过来的消息在 userContentController(_:didReceive:) 里处理，处理完用
// evaluateJavaScript 把结果送回页面的 window.__bridgeResult。
//
// 这是把三块原生专属界面（向导/设置/提醒编辑器）从"Mac 和 Windows 各写一份原生代码"
// 改成"两边共用同一份网页"这次重构的核心——具体背景见 PARITY.md。

enum BridgeError: LocalizedError {
    case scriptFailed(String)
    case unknownAction(String)

    var errorDescription: String? {
        switch self {
        case .scriptFailed(let message): return message
        case .unknownAction(let action): return "未知的桥接调用：\(action)"
        }
    }
}

class NativeBridge: NSObject, WKScriptMessageHandler {
    static let messageHandlerName = "native"

    weak var webView: WKWebView?

    init(webView: WKWebView) {
        self.webView = webView
    }

    static func install(on configuration: WKWebViewConfiguration, bridge: NativeBridge) {
        configuration.userContentController.add(bridge, name: messageHandlerName)
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard
            let body = message.body as? [String: Any],
            let id = body["id"] as? Int,
            let action = body["action"] as? String
        else { return }
        let payload = body["payload"] as? [String: Any] ?? [:]

        handle(action: action, payload: payload) { [weak self] result in
            self?.respond(id: id, result: result)
        }
    }

    private func respond(id: Int, result: Result<Any, Error>) {
        guard let webView = webView else { return }
        DispatchQueue.main.async {
            switch result {
            case .success(let value):
                // 用 {"v": ...} 包一层再取出来，规避 value 本身不是合法 JS 顶层表达式
                // （比如裸字符串/数字）时手动拼接 JS 代码字符串的转义麻烦。
                guard let wrapped = try? JSONSerialization.data(withJSONObject: ["v": value]),
                      let json = String(data: wrapped, encoding: .utf8) else {
                    webView.evaluateJavaScript("window.__bridgeResult(\(id), false, \"结果序列化失败\")")
                    return
                }
                webView.evaluateJavaScript("window.__bridgeResult(\(id), true, (\(json)).v)")
            case .failure(let error):
                guard let messageData = try? JSONSerialization.data(withJSONObject: [error.localizedDescription]),
                      let messageJSON = String(data: messageData, encoding: .utf8) else { return }
                webView.evaluateJavaScript("window.__bridgeResult(\(id), false, (\(messageJSON))[0])")
            }
        }
    }

    private func handle(action: String, payload: [String: Any], completion: @escaping (Result<Any, Error>) -> Void) {
        switch action {
        case "fetchCourses":
            let baseUrl = payload["baseUrl"] as? String ?? ""
            let token = payload["token"] as? String ?? ""
            runPythonJSON(["fetch_courses.py"], stdinObject: ["baseUrl": baseUrl, "token": token]) { result in
                completion(result.flatMap { output in
                    guard let data = output.data(using: .utf8),
                          let parsed = try? JSONSerialization.jsonObject(with: data) else {
                        return .failure(BridgeError.scriptFailed("课程列表解析失败"))
                    }
                    return .success(parsed)
                })
            }

        case "completeSetup":
            runPythonJSON(["write_config.py"], stdinObject: payload) { [weak self] result in
                switch result {
                case .failure(let error):
                    completion(.failure(error))
                case .success:
                    let remember = (payload["rememberMe"] as? Bool) ?? true
                    UserDefaults.standard.set(remember, forKey: "rememberLogin")
                    self?.runPython(["canvas_sync.py", "--refresh"]) { _ in
                        completion(.success(true))
                        DispatchQueue.main.async { delegate.finishSetupWizard() }
                    }
                }
            }

        case "getEnv":
            completion(.success(readEnvAll()))

        case "getPrefs":
            completion(.success([
                "theme": AppearanceMode.current.rawValue,
                "language": UserDefaults.standard.string(forKey: "settingsLanguage") ?? "zh",
            ]))

        case "setPrefs":
            if let theme = payload["theme"] as? String, let mode = AppearanceMode(rawValue: theme) {
                mode.apply()
            }
            if let language = payload["language"] as? String {
                UserDefaults.standard.set(language, forKey: "settingsLanguage")
            }
            completion(.success(true))

        case "syncNow":
            runPython(["canvas_sync.py", "--refresh"]) { _ in
                completion(.success(true))
                DispatchQueue.main.async { delegate.reloadMainWindowCurrentSection() }
            }

        case "logout":
            runPython(["clear_local_user_data.py"]) { _ in
                completion(.success(true))
                DispatchQueue.main.async { delegate.performLogoutTransition() }
            }

        case "openLogs":
            let logsPath = projectDir + "/logs"
            try? FileManager.default.createDirectory(atPath: logsPath, withIntermediateDirectories: true)
            NSWorkspace.shared.open(URL(fileURLWithPath: logsPath))
            completion(.success(true))

        case "openWizard":
            DispatchQueue.main.async { delegate.showSetupWizard() }
            completion(.success(true))

        case "getSchedule":
            completion(.success(ScheduleFile.load()))

        case "saveSchedule":
            let alarms = payload["alarms"] as? [[String: Any]] ?? []
            ScheduleFile.save(alarms)
            runPython(["update_schedule.py"]) { _ in
                completion(.success(true))
            }

        default:
            completion(.failure(BridgeError.unknownAction(action)))
        }
    }

    // MARK: - Python 子进程封装

    private func runPython(_ arguments: [String], completion: @escaping (Int32) -> Void) {
        let task = Process()
        task.currentDirectoryURL = URL(fileURLWithPath: projectDir)
        task.executableURL = URL(fileURLWithPath: projectDir + "/.venv/bin/python3")
        task.arguments = arguments
        task.terminationHandler = { process in
            DispatchQueue.main.async { completion(process.terminationStatus) }
        }
        do {
            try task.run()
        } catch {
            DispatchQueue.main.async { completion(-1) }
        }
    }

    // 从 stdin 传一份 JSON 给脚本、捕获 stdout——给 fetch_courses.py / write_config.py 用。
    // 小体量 JSON（几百字节到几 KB）不会撑爆管道缓冲区，用不着处理"边写边读"那套复杂逻辑。
    private func runPythonJSON(_ arguments: [String], stdinObject: [String: Any], completion: @escaping (Result<String, Error>) -> Void) {
        let task = Process()
        task.currentDirectoryURL = URL(fileURLWithPath: projectDir)
        task.executableURL = URL(fileURLWithPath: projectDir + "/.venv/bin/python3")
        task.arguments = arguments

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        task.standardInput = stdinPipe
        task.standardOutput = stdoutPipe
        task.standardError = stderrPipe

        task.terminationHandler = { process in
            let outData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let out = String(data: outData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let err = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            DispatchQueue.main.async {
                if process.terminationStatus == 0 {
                    completion(.success(out))
                } else {
                    completion(.failure(BridgeError.scriptFailed(err.isEmpty ? "脚本运行失败" : err)))
                }
            }
        }

        do {
            try task.run()
            if let data = try? JSONSerialization.data(withJSONObject: stdinObject) {
                stdinPipe.fileHandleForWriting.write(data)
            }
            stdinPipe.fileHandleForWriting.closeFile()
        } catch {
            DispatchQueue.main.async { completion(.failure(error)) }
        }
    }
}

// schedule.json 的读写现在完全交给网页那边的 JS 处理数据结构，原生这边只负责
// 原样存取这个文件——不用再维护 Alarm 这个 Swift 结构体了。
enum ScheduleFile {
    static var path: String { projectDir + "/schedule.json" }

    static func load() -> [[String: Any]] {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let alarms = json["alarms"] as? [[String: Any]] else {
            return [["id": "default", "hour": 8, "minute": 0, "enabled": true, "days": Array(0...6)]]
        }
        return alarms
    }

    static func save(_ alarms: [[String: Any]]) {
        guard let data = try? JSONSerialization.data(withJSONObject: ["alarms": alarms], options: [.prettyPrinted]) else { return }
        try? data.write(to: URL(fileURLWithPath: path))
    }
}
