import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/entities/network_log_entry.dart';
import '../../data/export/curl_exporter.dart';
import '../payload/built_in_viewers.dart';

/// Whether [entry] can be copied as a cURL command.
bool canCopyAsCurl(NetworkLogEntry entry) => buildCurlCommand(entry) != null;

/// Copies [entry] as a cURL command and explains any caveats.
Future<void> copyEntryAsCurl(
  BuildContext context,
  NetworkLogEntry entry, {
  String mask = '***',
}) async {
  final curl = buildCurlCommand(entry, redactionMask: mask);
  if (curl == null) return;
  final notes = [
    if (curl.containsRedactedValues) 'redacted values appear as $mask',
    if (curl.bodyOmitted) 'body not included',
  ];
  await copyWithConfirmation(
    context,
    curl.command,
    notes.isEmpty
        ? 'cURL command copied'
        : 'cURL command copied (${notes.join('; ')})',
  );
}

/// Copies [entry] as indented JSON.
Future<void> copyEntryAsJson(BuildContext context, NetworkLogEntry entry) =>
    copyWithConfirmation(
      context,
      const JsonEncoder.withIndent('  ').convert(entry.toJson()),
      'Request details copied',
    );

/// Shows copy actions for [entry] in a bottom sheet.
Future<void> showEntryActions(
  BuildContext context,
  NetworkLogEntry entry, {
  String mask = '***',
}) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (canCopyAsCurl(entry))
              ListTile(
                leading: const Icon(Icons.terminal),
                title: const Text('Copy as cURL'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  copyEntryAsCurl(context, entry, mask: mask);
                },
              ),
            ListTile(
              leading: const Icon(Icons.data_object),
              title: const Text('Copy as JSON'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                copyEntryAsJson(context, entry);
              },
            ),
          ],
        ),
      ),
    );
