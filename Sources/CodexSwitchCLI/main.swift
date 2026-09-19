import Foundation
import SwitchCore
#if os(macOS)
import AppKit
import Darwin

let help = """
Codex Switch — 终端和菜单栏共用同一份账号

codex-switch start                  打开窗口
codex-switch stop                   退出应用（不会退出你的 Codex 客户端）
codex-switch status                 查看运行状态及上次操作结果
codex-switch list                   列出账号名称、ID 和当前账号
codex-switch setup                  备份配置并启用文件登录保存
codex-switch save [名称]            保存当前登录
codex-switch add "名称"             打开官方页面添加账号
codex-switch add "名称" --device    设备码登录；用 status 查看设备码和验证地址
codex-switch switch "名称或ID"      切换；Codex 运行中则排队等待
codex-switch rename "名称或ID" "新名称"
codex-switch remove "名称或ID"      移除本工具保存的副本，不注销当前登录
codex-switch cancel                 取消登录或等待中的切换
codex-switch usage                  发起当前账号的用量刷新

任意命令加 --json 可输出结构化结果。add、switch 和 usage 可能仍在进行中，
用 status 查看后续结果。添加账号前请退出 Codex 客户端。未运行时会自动启动菜单栏应用。
"""

func run() throws -> Int32 {
    var arguments = Array(CommandLine.arguments.dropFirst())
    if arguments.isEmpty || arguments == ["--help"] || arguments == ["help"] { print(help); return 0 }
    let json = arguments.contains("--json")
    arguments.removeAll { $0 == "--json" }
    let command = try ControlCommand(arguments: arguments)
    let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Codex Switch")
    let socket = root.appendingPathComponent("control.sock").path
    let running = NSRunningApplication.runningApplications(withBundleIdentifier: "cc.atou.codex-switchbar")
    var response: ControlResponse
    if running.isEmpty && ["stop", "status"].contains(command.action) {
        response = ControlResponse(state: "stopped", message: "Codex Switch 已退出。")
    } else {
        if running.isEmpty {
            var pathSize: UInt32 = 0
            _ = _NSGetExecutablePath(nil, &pathSize)
            var pathBytes = [CChar](repeating: 0, count: Int(pathSize))
            guard _NSGetExecutablePath(&pathBytes, &pathSize) == 0 else { throw SwitchError.executableMissing }
            let binary = URL(fileURLWithPath: String(cString: pathBytes)).resolvingSymlinksInPath()
            let bundle = binary.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            guard bundle.pathExtension == "app", FileManager.default.fileExists(atPath: bundle.path) else {
                throw NSError(domain: "CodexSwitch", code: 1, userInfo: [NSLocalizedDescriptionKey: "请使用已安装应用中的 codex-switch 命令。"])
            }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["-g", "-a", bundle.path, "--args", "--background"]
            try process.run(); process.waitUntilExit()
            guard process.terminationStatus == 0 else { throw SwitchError.processFailed }
        }
        let deadline = Date().addingTimeInterval(10)
        while !FileManager.default.fileExists(atPath: socket) && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        let data = try LocalControlClient.request(path: socket, data: JSONEncoder().encode(command))
        response = try JSONDecoder().decode(ControlResponse.self, from: data)
        if command.action == "stop" && response.ok {
            let deadline = Date().addingTimeInterval(10)
            while !NSRunningApplication.runningApplications(withBundleIdentifier: "cc.atou.codex-switchbar").isEmpty && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.05)
            }
            guard NSRunningApplication.runningApplications(withBundleIdentifier: "cc.atou.codex-switchbar").isEmpty else { throw SwitchError.timeout }
            response = ControlResponse(state: "stopped", message: "Codex Switch 已退出。")
        }
    }
    if json {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        print(String(decoding: try encoder.encode(response), as: UTF8.self))
    } else {
        let summary = "\(response.state)\(response.message.map { " · " + $0 } ?? "")\n"
        (response.ok ? FileHandle.standardOutput : FileHandle.standardError).write(Data(summary.utf8))
        if let code = response.loginCode, let url = response.verificationURL {
            print("验证地址：\(url)\n设备码：\(code)")
        }
        for account in response.accounts {
            print("\(account.active ? "*" : " ") \(account.name)  \(account.id.uuidString)")
            if command.action == "usage", let usage = account.usage, account.active {
                let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                print(String(decoding: try encoder.encode(usage), as: UTF8.self))
            }
        }
    }
    return response.ok ? 0 : 1
}
do { exit(try run()) }
catch { FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8)); exit(1) }
#else
print("Codex Switch CLI requires macOS.")
#endif
