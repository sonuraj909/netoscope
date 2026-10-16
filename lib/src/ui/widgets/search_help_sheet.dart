import 'package:flutter/material.dart';

import '../theme/inspector_theme.dart';

/// Explains the inspector's search syntax, with tappable examples.
class SearchHelpSheet extends StatelessWidget {
  /// Creates the sheet. [onExample] receives a tapped example query.
  const SearchHelpSheet({super.key, required this.onExample});

  /// Called with an example query to apply.
  final ValueChanged<String> onExample;

  static const List<(String, String, String)> _rows = [
    ('method:', 'HTTP method', 'method:POST'),
    ('status:', 'code, class, range or outcome', 'status:>=400'),
    ('host:  path:  url:', 'part of the URL', 'path:/users'),
    ('duration:', 'ms, s or a range', 'duration:>500'),
    ('size:', 'response size', 'size:>100kb'),
    ('protocol:', 'http, ws, sse, grpc, mqtt', 'protocol:ws'),
    ('tag:', 'calls tagged in code', 'tag:login-flow'),
    ('is:', 'slow, error, graphql, duplicate, n+1, webhook', 'is:n+1'),
    ('op:', 'GraphQL operation name', 'op:GetUser'),
    ('header:  body:', 'header name or body text', 'body:"not found"'),
    (
      'event:  topic:  source:',
      'SSE event, MQTT topic, native source',
      'source:ios'
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        children: [
          Text(
            'Search syntax',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            'Combine free text with filters; every term must match. '
            'Separate alternatives with commas (method:GET,POST), negate with '
            '- or ! (-status:2xx), and quote values with spaces.',
            style: theme.textTheme.bodySmall?.copyWith(color: muted),
          ),
          const SizedBox(height: 12),
          for (final (key, meaning, example) in _rows)
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => onExample(example),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 128,
                      child: Text(
                        key,
                        style: codeTextStyle.copyWith(
                          fontSize: 12.5,
                          height: 1.4,
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(meaning, style: theme.textTheme.bodySmall),
                          Text(
                            example,
                            style: codeTextStyle.copyWith(
                              fontSize: 12,
                              height: 1.4,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
