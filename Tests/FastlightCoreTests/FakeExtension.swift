import Foundation
@testable import FastlightCore

/// Throwaway extensions written as /bin/sh scripts, so tests exercise real
/// child processes and pipes.
enum FakeExtension {
    /// The usual reply loop: answers searches with one item titled after the
    /// query. Queries starting with "slow" sleep a second first, "crash"
    /// exits with status 3, "garbage" prints noise.
    static let echo = #"""
    echo '{"type":"ready","protocol":1}'
    while IFS= read -r line; do
      id=$(printf '%s' "$line" | sed -n 's/.*"id":\([0-9]*\).*/\1/p')
      [ -z "$id" ] && { printf '%s\n' "$line" >> notes.txt; continue; }
      q=$(printf '%s' "$line" | sed -n 's/.*"query":"\([^"]*\)".*/\1/p')
      case "$q" in
        slow*) sleep 1 ;;
        crash*) exit 3 ;;
        garbage*) echo "not json"; echo "{}" ;;
      esac
      printf '{"id":%s,"items":[{"id":"a","title":"%s"}]}\n' "$id" "$q"
    done
    """#

    static func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("fl-ext-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// A folder with `run.sh` (the script) and, unless `manifest` is nil,
    /// an extension.json.
    @discardableResult
    static func folder(in root: URL? = nil, name: String = "ext", id: String = "com.test.ext", version: String = "1.0.0",
                       keywords: [String] = ["t"], global: Bool = false, script: String = echo,
                       manifest: String? = "") throws -> URL {
        let base = try root ?? tempDir()
        let dir = base.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let run = dir.appendingPathComponent("run.sh")
        try ("#!/bin/sh\n" + script + "\n").write(to: run, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: run.path)
        if let manifest {
            let kw = keywords.map { "\"\($0)\"" }.joined(separator: ",")
            let json = manifest.isEmpty
                ? #"{"id":"\#(id)","name":"Test","version":"\#(version)","keywords":[\#(kw)],"command":["run.sh"]\#(global ? #","global":{"maxResults":2,"minQueryLength":1}"# : "")}"#
                : manifest
            try json.write(to: dir.appendingPathComponent("extension.json"), atomically: true, encoding: .utf8)
        }
        return dir
    }

    static func process(_ script: String = echo, configure: (inout ExtensionProcess.Config) -> Void = { _ in }) throws
        -> (ExtensionProcess, URL) {
        let dir = try folder(script: script, manifest: nil)
        var config = ExtensionProcess.Config(executable: dir.appendingPathComponent("run.sh"), directory: dir,
                                             environment: ["PATH": "/usr/bin:/bin"],
                                             logURL: dir.appendingPathComponent("log.txt"))
        configure(&config)
        return (ExtensionProcess(config: config), dir)
    }
}

extension ExtensionProcess {
    /// The callback API, awaited.
    func ask(_ message: OutgoingMessage, timeout: TimeInterval = 5) async -> Result<Data, ExtensionError> {
        await withCheckedContinuation { c in
            request(message, timeout: timeout) { c.resume(returning: $0) }
        }
    }

    func search(_ q: String, timeout: TimeInterval = 5) async throws -> [String] {
        let line = try await ask(.search(query: q, mode: .keyword, limit: 10), timeout: timeout).get()
        return try ExtensionReply.items(from: line).map(\.title)
    }
}

/// Polls until a condition holds, for state that changes on another thread.
func eventually(_ timeout: TimeInterval = 5, _ condition: () -> Bool) async -> Bool {
    let end = Date().addingTimeInterval(timeout)
    while Date() < end {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return condition()
}
