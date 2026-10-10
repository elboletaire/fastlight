import Darwin
import Foundation

/// A minimal blocking AF_UNIX stream socket that speaks newline-delimited
/// messages.
final class UnixSocket {
    private let fd: Int32
    private var buffer = Data()

    /// `timeout` bounds each read and write, so a hung peer can't block
    /// the caller forever; nil (or not positive) waits as long as it takes.
    init(path: String, timeout: TimeInterval? = nil) throws {
        // A local until it's connected: once self.fd is set, a throw runs
        // deinit, which would close the number a second time, by then maybe
        // another thread's file.
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw Self.posixError("socket") }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let maxLen = MemoryLayout.size(ofValue: addr.sun_path)
        guard path.utf8.count < maxLen else {
            close(fd)
            throw FSearchError.unreachable("socket path too long")
        }
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            raw.copyBytes(from: path.utf8)
            raw[path.utf8.count] = 0
        }
        let ok = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard ok == 0 else {
            let err = Self.posixError("connect")
            close(fd)
            throw err
        }
        self.fd = fd
        // Don't let a dead daemon kill us with SIGPIPE.
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        if let timeout, timeout > 0 {
            let secs = Int(timeout)
            var tv = timeval(tv_sec: secs, tv_usec: Int32((timeout - Double(secs)) * 1_000_000))
            let size = socklen_t(MemoryLayout<timeval>.size)
            setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, size)
            setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, size)
        }
    }

    deinit { close(fd) }

    func writeLine(_ data: Data) throws {
        var out = data
        out.append(0x0A)
        try out.withUnsafeBytes { raw in
            var sent = 0
            while sent < raw.count {
                let n = write(fd, raw.baseAddress! + sent, raw.count - sent)
                if n < 0 {
                    if errno == EINTR { continue }
                    if errno == EAGAIN { throw FSearchError.timedOut }
                    throw Self.posixError("write")
                }
                sent += n
            }
        }
    }

    func readLine() throws -> Data {
        var chunk = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            if let nl = buffer.firstIndex(of: 0x0A) {
                let line = buffer[buffer.startIndex..<nl]
                buffer.removeSubrange(buffer.startIndex...nl)
                return Data(line)
            }
            let n = read(fd, &chunk, chunk.count)
            if n < 0 {
                if errno == EINTR { continue }
                if errno == EAGAIN { throw FSearchError.timedOut }
                throw Self.posixError("read")
            }
            if n == 0 { throw FSearchError.unreachable("daemon closed the connection") }
            buffer.append(contentsOf: chunk[0..<n])
        }
    }

    private static func posixError(_ op: String) -> FSearchError {
        .unreachable("\(op): \(String(cString: strerror(errno)))")
    }
}
