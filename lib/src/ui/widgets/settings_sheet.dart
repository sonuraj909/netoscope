import 'package:flutter/material.dart';

import '../../config/netoscope_settings.dart';
import '../../config/network_logger_config.dart';
import '../../network_inspector.dart';
import '../theme/inspector_theme.dart';

/// Runtime switches for recording, the floating button, the notification
/// and the inspector theme.
class InspectorSettingsSheet extends StatelessWidget {
  /// Creates the sheet for [netoscope].
  const InspectorSettingsSheet({super.key, required this.netoscope});

  /// The logger whose switches are shown.
  final Netoscope netoscope;

  @override
  Widget build(BuildContext context) => InspectorThemeScope(
        netoscope: netoscope,
        child: Builder(builder: _buildSurface),
      );

  // Drawn here rather than by the modal, so it follows theme switches.
  Widget _buildSurface(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      // A fresh subtree per brightness: Material and ListTile otherwise fade
      // text colors over the instant surface change, leaving it unreadable.
      key: ValueKey(theme.brightness),
      color: theme.bottomSheetTheme.backgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 22),
            child: Container(
              width: 32,
              height: 4,
              decoration: BoxDecoration(
                color:
                    theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Flexible(child: _buildContent(context)),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
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
                  ListTile(
                    leading: const Icon(Icons.contrast),
                    title: const Text('Theme'),
                    subtitle:
                        const Text('Follow the app, or force light or dark.'),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: SegmentedButton<InspectorThemeMode>(
                      segments: const [
                        ButtonSegment(
                          value: InspectorThemeMode.system,
                          icon: Icon(Icons.brightness_auto_outlined),
                          label: Text('System'),
                        ),
                        ButtonSegment(
                          value: InspectorThemeMode.light,
                          icon: Icon(Icons.light_mode_outlined),
                          label: Text('Light'),
                        ),
                        ButtonSegment(
                          value: InspectorThemeMode.dark,
                          icon: Icon(Icons.dark_mode_outlined),
                          label: Text('Dark'),
                        ),
                      ],
                      selected: {settings.themeMode},
                      showSelectedIcon: false,
                      onSelectionChanged: (selection) =>
                          netoscope.setInspectorThemeMode(selection.single),
                    ),
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
