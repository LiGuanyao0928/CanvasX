import Foundation

// 0 = 周日 ... 6 = 周六，跟 launchd 的 Weekday 编号一致
struct Alarm: Codable, Identifiable {
    var id: String
    var hour: Int
    var minute: Int
    var enabled: Bool
    var days: [Int]

    static let dayLabels = ["日", "一", "二", "三", "四", "五", "六"]

    var timeText: String {
        String(format: "%02d:%02d", hour, minute)
    }

    var repeatText: String {
        let sorted = Set(days)
        if sorted.count == 7 { return "每天" }
        if sorted == Set([1, 2, 3, 4, 5]) { return "周一至周五" }
        if sorted == Set([0, 6]) { return "周六、周日" }
        if sorted.isEmpty { return "不重复" }
        return sorted.sorted().map { "周\(Alarm.dayLabels[$0])" }.joined(separator: "、")
    }
}

struct Schedule: Codable {
    var alarms: [Alarm]
}

enum ScheduleStore {
    static let path = projectDir + "/schedule.json"

    static func load() -> [Alarm] {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let schedule = try? JSONDecoder().decode(Schedule.self, from: data) else {
            return [Alarm(id: UUID().uuidString, hour: 8, minute: 0, enabled: true, days: Array(0...6))]
        }
        return schedule.alarms
    }

    static func save(_ alarms: [Alarm]) {
        let schedule = Schedule(alarms: alarms)
        guard let data = try? JSONEncoder().encode(schedule) else { return }
        try? data.write(to: URL(fileURLWithPath: path))
        applyToLaunchd()
    }

    static func applyToLaunchd() {
        let task = Process()
        task.currentDirectoryURL = URL(fileURLWithPath: projectDir)
        task.executableURL = URL(fileURLWithPath: projectDir + "/.venv/bin/python3")
        task.arguments = ["update_schedule.py"]
        try? task.run()
    }
}
