/// Debug-time network logging and inspection for Flutter.
///
/// Start with [Netoscope], attach [Netoscope.dioInterceptor] or
/// [Netoscope.httpClient] to your clients, and optionally open the
/// [NetworkInspector].
library;

export 'src/adapters/realtime/connection_recorder.dart' show ConnectionRecorder;
export 'src/adapters/realtime/grpc_call_recorder.dart' show GrpcCallRecorder;
export 'src/adapters/realtime/mqtt_recorder.dart' show MqttRecorder;
export 'src/adapters/realtime/sse_recorder.dart' show SseRecorder;
export 'src/adapters/realtime/web_socket_recorder.dart' show WebSocketRecorder;
export 'src/config/netoscope_settings.dart' show NetoscopeSettings;
export 'src/config/network_logger_config.dart'
    show ConsoleLogLevel, NetworkLoggerConfig;
export 'src/core/contracts/network_activity_notifier.dart'
    show NetworkActivityNotifier, NetworkActivitySummary;
export 'src/core/contracts/network_log_sink.dart' show NetworkLogSink;
export 'src/core/contracts/network_log_store.dart' show NetworkLogStore;
export 'src/core/contracts/payload_decoder.dart'
    show PayloadContext, PayloadDecoder;
export 'src/core/entities/network_log_body.dart'
    show NetworkBodyKind, NetworkLogBody;
export 'src/core/entities/graphql_details.dart'
    show GraphQLDetails, GraphQLError, GraphQLOperation, GraphQLOperationType;
export 'src/core/entities/network_event_kind.dart'
    show
        ConnectionLifecycle,
        MessageDirection,
        NetworkEventKind,
        NetworkProtocol;
export 'src/core/entities/payload_format.dart' show PayloadFormat;
export 'src/core/entities/protocol_details.dart'
    show
        GrpcCallType,
        GrpcDetails,
        MqttDetails,
        ProtocolDetails,
        SseDetails,
        TransferDetails,
        TransferDirection,
        WebSocketDetails,
        WebSocketFrameType;
export 'src/core/entities/webhook_details.dart'
    show WebhookDetails, WebhookOutcome, WebhookSource;
export 'src/core/entities/network_log_entry.dart'
    show NetworkLogEntry, NetworkLogOutcome;
export 'src/core/entities/network_log_error.dart'
    show NetworkErrorType, NetworkLogError;
export 'src/data/sinks/console_network_log_sink.dart'
    show ConsoleNetworkLogSink;
export 'src/data/storage/in_memory_network_log_store.dart'
    show InMemoryNetworkLogStore;
export 'src/network_inspector.dart' show Netoscope;
export 'src/protocols/webhook/webhook_config.dart'
    show WebhookAttempt, WebhookConfig;
export 'src/protocols/webhook/webhook_delivery_record.dart'
    show WebhookDeliveryRecord;
export 'src/security/protobuf_payload_decoder.dart' show ProtobufPayloadDecoder;
export 'src/ui/payload/payload_viewer.dart' show PayloadViewer;
export 'src/ui/network_inspector.dart'
    show NetoscopeInspector, NetworkInspector;
export 'src/ui/widgets/network_inspector_button.dart'
    show NetworkInspectorButton, NetworkInspectorOverlay;
