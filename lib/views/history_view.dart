import 'dart:io';
import 'package:flutter/material.dart';
import '../models/transfer_record.dart';
import '../services/storage/history_repository.dart';
import '../theme/gemini_theme.dart';
import '../theme/responsive.dart';

/// Dedicated History view displaying persistent transfer logs grouped by date
/// with "Open File", "Show in Folder", and "Clear History" capabilities.
class HistoryView extends StatelessWidget {
  final HistoryRepository historyRepository;

  const HistoryView({
    super.key,
    required this.historyRepository,
  });

  void _confirmClear(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: GeminiTheme.surfaceContainer,
        title: const Row(
          children: [
            Icon(Icons.delete_sweep_rounded, color: GeminiTheme.coralError),
            SizedBox(width: 10),
            Text('Clear History?', style: TextStyle(color: GeminiTheme.textPrimary)),
          ],
        ),
        content: const SingleChildScrollView(
          child: Text(
            'This will remove all transfer records from the log. Your physical downloaded files will not be deleted.',
            style: TextStyle(color: GeminiTheme.textSecondary, fontSize: 13),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel', style: TextStyle(color: GeminiTheme.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: GeminiTheme.coralError),
            onPressed: () {
              historyRepository.clearHistory();
              Navigator.of(ctx).pop();
            },
            child: const Text('Clear All'),
          ),
        ],
      ),
    );
  }

  void _showRecordActions(BuildContext context, TransferRecord record) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: GeminiTheme.surfaceContainer,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 600,
              maxHeight: context.screenHeight * 0.85,
            ),
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: context.responsiveHorizontalPadding,
                vertical: 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: GeminiTheme.surfaceVariant,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.insert_drive_file_rounded, color: GeminiTheme.cyan),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          record.fileName,
                          style: const TextStyle(
                            color: GeminiTheme.textPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '${record.formattedSize} • ${record.formattedTime} • ${record.peerName}',
                          style: const TextStyle(color: GeminiTheme.textSecondary, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.open_in_new_rounded, color: GeminiTheme.cyan),
                title: const Text('Open File', style: TextStyle(color: GeminiTheme.textPrimary)),
                subtitle: const Text('Launch default system viewer', style: TextStyle(color: GeminiTheme.textMuted, fontSize: 11)),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  final ok = await HistoryRepository.openFile(record.filePath);
                  if (!ok && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Could not open file: ${record.fileName}')),
                    );
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.folder_open_rounded, color: GeminiTheme.lavender),
                title: Text(
                  Platform.isWindows ? 'Show in Windows Explorer' : 'Show in Folder',
                  style: const TextStyle(color: GeminiTheme.textPrimary),
                ),
                subtitle: Text(record.filePath, style: const TextStyle(color: GeminiTheme.textMuted, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  await HistoryRepository.showInFolder(record.filePath);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded, color: GeminiTheme.coralError),
                title: const Text('Remove from History', style: TextStyle(color: GeminiTheme.coralError)),
                onTap: () {
                  historyRepository.deleteRecord(record.id);
                  Navigator.of(ctx).pop();
                },
              ),
            ],
          ),
        ),
      ),
    ),
    ),
  );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: historyRepository,
      builder: (context, _) {
        final grouped = historyRepository.getGroupedRecords();
        final totalCount = historyRepository.records.length;

        return Scaffold(
          backgroundColor: GeminiTheme.deepVoid,
          appBar: AppBar(
            backgroundColor: GeminiTheme.deepVoid,
            title: Row(
              children: [
                const Text('Transfer History', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: GeminiTheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Text(
                    '$totalCount',
                    style: const TextStyle(color: GeminiTheme.cyan, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            actions: [
              if (totalCount > 0)
                IconButton(
                  icon: const Icon(Icons.delete_sweep_rounded, color: GeminiTheme.textMuted),
                  tooltip: 'Clear history log',
                  onPressed: () => _confirmClear(context),
                ),
            ],
          ),
          body: totalCount == 0
              ? _buildEmptyState()
              : Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 860),
                    child: ListView.builder(
                      padding: EdgeInsets.symmetric(
                        horizontal: context.responsiveHorizontalPadding,
                        vertical: context.isMobile ? 12 : 20,
                      ),
                      itemCount: grouped.keys.length,
                      itemBuilder: (context, groupIndex) {
                        final dateHeader = grouped.keys.elementAt(groupIndex);
                        final recordsInGroup = grouped[dateHeader]!;

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Date section header
                            Padding(
                              padding: const EdgeInsets.only(top: 14, bottom: 8, left: 4),
                              child: Text(
                                dateHeader.toUpperCase(),
                                style: const TextStyle(
                                  color: GeminiTheme.textMuted,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.2,
                                ),
                              ),
                            ),
                            // Transfer entries
                            ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: recordsInGroup.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 8),
                              itemBuilder: (context, i) {
                                final record = recordsInGroup[i];
                                return _buildRecordTile(context, record);
                              },
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
        );
      },
    );
  }

  Widget _buildRecordTile(BuildContext context, TransferRecord record) {
    final isSent = record.direction == TransferDirection.sent;
    final isCompleted = record.status == TransferRecordStatus.completed;

    return InkWell(
      onTap: () => _showRecordActions(context, record),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: GeminiTheme.surfaceContainer,
          borderRadius: BorderRadius.circular(16),
          border: GeminiTheme.thinBorder,
        ),
        child: Row(
          children: [
            // Direction badge (Sent vs Received)
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: isSent
                    ? GeminiTheme.electricBlue.withOpacity(0.18)
                    : GeminiTheme.lavender.withOpacity(0.18),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSent
                      ? GeminiTheme.electricBlue.withOpacity(0.4)
                      : GeminiTheme.lavender.withOpacity(0.4),
                ),
              ),
              child: Icon(
                isSent ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                color: isSent ? GeminiTheme.cyan : GeminiTheme.lavender,
                size: 20,
              ),
            ),
            const SizedBox(width: 14),

            // File Name & Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    record.fileName,
                    style: const TextStyle(
                      color: GeminiTheme.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 6,
                    runSpacing: 2,
                    children: [
                      Text(
                        isSent ? 'To: ${record.peerName}' : 'From: ${record.peerName}',
                        style: const TextStyle(color: GeminiTheme.textSecondary, fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '•  ${record.formattedSize}',
                        style: const TextStyle(color: GeminiTheme.textMuted, fontSize: 12),
                      ),
                      if (record.transferDurationMs > 0)
                        Text(
                          '•  ${record.formattedSpeed}',
                          style: const TextStyle(color: GeminiTheme.cyan, fontSize: 11, fontWeight: FontWeight.w500),
                        ),
                    ],
                  ),
                ],
              ),
            ),

            // Time & Status Badge
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  record.formattedTime,
                  style: const TextStyle(color: GeminiTheme.textMuted, fontSize: 11),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isCompleted
                        ? GeminiTheme.emeraldGreen.withOpacity(0.12)
                        : GeminiTheme.coralError.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    isCompleted ? 'DONE' : 'FAILED',
                    style: TextStyle(
                      color: isCompleted ? GeminiTheme.emeraldGreen : GeminiTheme.coralError,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: GeminiTheme.surfaceContainer,
              border: GeminiTheme.thinBorder,
            ),
            child: const Icon(Icons.history_rounded, size: 36, color: GeminiTheme.textMuted),
          ),
          const SizedBox(height: 16),
          const Text(
            'No Transfer History Yet',
            style: TextStyle(
              color: GeminiTheme.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Sent and received files will appear here automatically.',
            style: TextStyle(color: GeminiTheme.textSecondary, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
