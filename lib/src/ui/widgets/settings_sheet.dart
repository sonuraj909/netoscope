import 'package:flutter/material.dart';

import '../../config/netoscope_settings.dart';
import '../../network_inspector.dart';

/// Runtime switches for recording, the floating button and the
/// notification.
class InspectorSettingsSheet extends StatelessWidget {
  /// Creates the sheet for [netoscope].
  const InspectorSettingsSheet({super.key, required this.netoscope});

  /// The logger whose switches are shown.
  final Netoscope netoscope;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return StreamBuilder<NetoscopeSettings>(
      stream: netoscope.settingsChanges,
      initialData: netoscope.settings,
      builder: (context, _) {
        final settings = netoscope.settings;
        final hasNotifier = netoscope.hasNotifier;
        return SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Text(
                      'Inspector settings',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  SwitchListTile(
                    secondary: const Icon(Icons.fiber_manual_record_outlined),
                    title: const Text('Record network activity'),
                    subtitle: Text(
                      settings.recording
                          ? 'Capturing calls from attached clients.'
                          : 'Paused: new calls are not captured.',
                    ),
                    value: settings.recording,
                    onChanged: netoscope.setLoggingEnabled,
                  ),
                  SwitchListTile(
                    secondary: const Icon(Icons.bubble_chart_outlined),
                    title: const Text('Floating button'),
                    subtitle: const Text(
                        'A shortcut to the inspector over your app.'),
                    value: settings.floatingButton,
                    onChanged: netoscope.setFloatingButtonEnabled,
                  ),
                  SwitchListTile(
                    secondary: const Icon(Icons.notifications_none),
                    title: const Text('Notification'),
                    subtitle: Text(
                      hasNotifier
                          ? 'Shows recent activity; tap it to open the inspector.'
                          : 'Attach a notifier (netoscope_notifications) to enable.',
                    ),
                    value: hasNotifier && settings.notification,
                    onChanged:
                        hasNotifier ? netoscope.setNotificationEnabled : null,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
