/// Receives one log line per call. Injected so the CLI can print to stdout
/// with its own formatting and the GUI can forward to `os.Logger`.
public typealias LogHandler = @Sendable (String) -> Void
