import Darwin

/// SIGPIPE, ignored for the whole process: a write to a pipe or socket
/// whose reader is gone then fails with EPIPE instead of killing us.
///
/// Every socket and pipe Fastlight writes to already sets SO_NOSIGPIPE or
/// F_SETNOSIGPIPE, but those are per descriptor. A write that lands on a
/// descriptor someone else opened (a number closed and reused under a
/// writer) still raised SIGPIPE, which twice killed a whole test run on CI.
/// Ignoring it process-wide makes any such write an error, never a crash.
public enum BrokenPipes {
    private static let once: Void = { _ = signal(SIGPIPE, SIG_IGN) }()

    /// Idempotent and cheap; called by the app at launch and by whatever
    /// opens a socket or starts a process to talk to.
    public static func ignore() { once }

    /// Whether SIGPIPE is currently ignored, for tests.
    public static var ignored: Bool {
        var current = sigaction()
        sigaction(SIGPIPE, nil, &current)
        // The handler union holds a C function pointer; SIG_IGN is (void *)1.
        return unsafeBitCast(current.__sigaction_u, to: Int.self) == 1
    }
}
