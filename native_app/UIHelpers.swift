import Cocoa

// .env 目前只有几行 KEY=VALUE——不用引入解析库，读全部键值对给 Bridge.swift 的
// getEnv 桥接调用用（设置面板网页显示当前 Canvas 网址）。
func readEnvAll() -> [String: String] {
    let envPath = projectDir + "/.env"
    guard let content = try? String(contentsOfFile: envPath, encoding: .utf8) else { return [:] }
    var result: [String: String] = [:]
    for line in content.split(separator: "\n") {
        let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { continue }
        result[parts[0]] = parts[1].trimmingCharacters(in: .whitespaces)
    }
    return result
}
