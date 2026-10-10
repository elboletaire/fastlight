import Darwin
import Foundation
import Testing
@testable import FastlightCore

@Suite struct UnixSocketDescriptorTests {
    /// A failed connect closed its descriptor, then deinit closed the same
    /// number again: by then it could belong to another thread's file (a
    /// pipe to an extension, say). Files opened meanwhile must stay open.
    @Test func aFailedConnectClosesOnlyItsOwnSocket() {
        let tooLong = "/tmp/" + String(repeating: "x", count: 200)
        let stop = Counter(), finished = Counter(), broken = Counter()
        let openers = 4
        for _ in 0..<openers {
            Thread.detachNewThread {
                while stop.value == 0 {
                    let fd = open("/dev/null", O_RDONLY | O_CLOEXEC)
                    guard fd >= 0 else { continue }
                    var st = stat()
                    // Closed under us, or closed and reused for a socket.
                    if fstat(fd, &st) != 0 || (st.st_mode & S_IFMT) != S_IFCHR {
                        broken.bump()
                    } else {
                        close(fd)
                    }
                }
                finished.bump()
            }
        }
        DispatchQueue.concurrentPerform(iterations: 4) { _ in
            for _ in 0..<20_000 { _ = try? UnixSocket(path: tooLong) }
        }
        stop.bump()
        while finished.value < openers { Thread.sleep(forTimeInterval: 0.001) }
        #expect(broken.value == 0)
    }
}
