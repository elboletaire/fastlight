import Darwin
import Foundation
import Testing
@testable import FastlightCore

@Suite struct BrokenPipesTests {
    @Test func writingToAClosedPipeFailsInsteadOfKillingTheProcess() throws {
        BrokenPipes.ignore()
        #expect(BrokenPipes.ignored)
        // A plain pipe, with no F_SETNOSIGPIPE: only the process-wide setting
        // keeps this write from raising SIGPIPE.
        var fds: [Int32] = [0, 0]
        try #require(pipe(&fds) == 0)
        close(fds[0])
        defer { close(fds[1]) }
        let n = "x".withCString { write(fds[1], $0, 1) }
        #expect(n == -1 && errno == EPIPE)
    }

    @Test func socketsAndProcessesIgnoreItForUs() throws {
        // Opening a UnixSocket (even one that can't connect) sets it up.
        _ = try? UnixSocket(path: "/nonexistent/fastlight.sock")
        #expect(BrokenPipes.ignored)
    }
}
