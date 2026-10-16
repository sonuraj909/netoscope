/// Debug-time network logging and inspection for Flutter.
///
/// Start with [Netoscope], attach [Netoscope.dioInterceptor] or
/// [Netoscope.httpClient] to your clients, and optionally open the
/// [NetworkInspector].
library;

export 'src/config/network_logger_config.dart'
    show ConsoleLogLevel, NetworkLoggerConfig;
export 'src/core/contracts/network_log_sink.dart' show NetworkLogSink;
export 'src/core/contracts/network_log_store.dart' show NetworkLogStore;
export 'src/core/entities/network_log_body.dart'
    show NetworkBodyKind, NetworkLogBody;
export 'src/core/entities/network_log_entry.dart'
    show NetworkLogEntry, NetworkLogOutcome;
export 'src/core/entities/network_log_error.dart'
    show NetworkErrorType, NetworkLogError;
export 'src/data/sinks/console_network_log_sink.dart'
    show ConsoleNetworkLogSink;
export 'src/data/storage/in_memory_network_log_store.dart'
    show InMemoryNetworkLogStore;
export 'src/network_inspector.dart' show Netoscope;
export 'src/ui/network_inspector.dart'
    show NetoscopeInspector, NetworkInspector;
export 'src/ui/widgets/network_inspector_button.dart'
    show NetworkInspectorButton, NetworkInspectorOverlay;
