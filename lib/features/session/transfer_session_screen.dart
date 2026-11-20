import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/server/shared_file.dart';
import '../../core/utils/transfer_metrics.dart';
import '../../state/share_controller.dart';
import '../../state/share_scope.dart';
import '../../theme/app_theme.dart';
import '../common/ui_kit.dart';

/// WhatsApp-style in-room screen: chat bubbles plus live transfer cards.
class TransferSessionScreen extends StatefulWidget {
  const TransferSessionScreen({super.key});

  /// True while a room is on screen. Link events keep firing during a session
  /// (every inbound message, every upload tick), so the hand-off paths consult
  /// this to avoid tearing the room down and building a fresh one.
  static bool get isOpen => _openRooms > 0;
  static int _openRooms = 0;

  @override
  State<TransferSessionScreen> createState() => _TransferSessionScreenState();
}

class _TransferSessionScreenState extends State<TransferSessionScreen> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    TransferSessionScreen._openRooms++;
  }

  @override
  void dispose() {
    TransferSessionScreen._openRooms--;
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _sendText() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    ShareScope.of(context).sendText(text);
    _textController.clear();
    _scrollToEnd();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _attachFiles() async {
    final controller = ShareScope.of(context);
    final picked = await FilePickerBridge.pick();
    if (picked.isEmpty) return;
    controller.shareFiles(picked);
    _scrollToEnd();
  }

  @override
  Widget build(BuildContext context) {
    final controller = ShareScope.of(context);
    final entries = controller.entries;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary.withValues(alpha: 0.18),
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.5)),
              ),
              child: const Icon(Icons.devices_rounded, size: 18, color: AppColors.primary),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    controller.peerConnected ? 'Connected Device' : 'Waiting for device',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  Text(
                    controller.serverUrl ?? 'Room not started',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: StatusPill(
                label: controller.peerConnected ? 'Online' : 'Idle',
                icon: Icons.circle,
                color: controller.peerConnected ? AppColors.success : AppColors.textMuted,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: entries.isEmpty
                ? const EmptyState(
                    icon: Icons.forum_rounded,
                    title: 'Room is quiet',
                    subtitle: 'Send a message or attach files to start the session.',
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                    itemCount: entries.length,
                    itemBuilder: (context, i) {
                      final entry = entries[i];
                      if (entry is ChatMessage) {
                        return _ChatBubble(message: entry);
                      }
                      return _TransferCard(item: entry as TransferItem);
                    },
                  ),
          ),
          _InputBar(
            controller: _textController,
            onSend: _sendText,
            onAttach: _attachFiles,
          ),
        ],
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final incoming = message.incoming;
    final bubbleColor = incoming ? AppColors.surfaceHigh : AppColors.primary;

    return Align(
      alignment: incoming ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.74,
        ),
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(incoming ? 4 : 16),
            bottomRight: Radius.circular(incoming ? 16 : 4),
          ),
          border: incoming ? Border.all(color: AppColors.border) : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(
              message.text,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, height: 1.35),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  _timeLabel(message.time),
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 10.5),
                ),
                const SizedBox(width: 6),
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: message.text));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Message copied')),
                    );
                  },
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Row(
                      children: [
                        Icon(Icons.copy_rounded, size: 13, color: AppColors.textSecondary),
                        SizedBox(width: 3),
                        Text(
                          'Copy',
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
                        ),
                      ],
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
}

class _TransferCard extends StatelessWidget {
  const _TransferCard({required this.item});

  final TransferItem item;

  @override
  Widget build(BuildContext context) {
    final controller = ShareScope.of(context);
    final done = item.status == TransferStatus.completed;
    final cancelled = item.status == TransferStatus.cancelled;
    final paused = item.status == TransferStatus.paused;
    final shared = item.status == TransferStatus.shared;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: done ? AppColors.success.withValues(alpha: 0.5) : AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CategoryAvatar(category: item.category, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TruncatedName(name: item.fileName, maxLength: 30),
                    const SizedBox(height: 3),
                    Text(
                      _statusLine(item),
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              if (shared)
                const StatusPill(label: 'Shared', icon: Icons.cloud_done_rounded)
              else if (done)
                const StatusPill(
                  label: 'Done',
                  icon: Icons.check_circle_rounded,
                  color: AppColors.success,
                )
              else if (cancelled)
                const StatusPill(
                  label: 'Cancelled',
                  icon: Icons.cancel_rounded,
                  color: AppColors.danger,
                )
              else if (paused)
                const StatusPill(
                  label: 'Paused',
                  icon: Icons.pause_circle_rounded,
                  color: AppColors.warning,
                )
              else
                StatusPill(
                  label: item.speedString.isEmpty ? 'Transferring' : item.speedString,
                  icon: Icons.bolt_rounded,
                  color: AppColors.accent,
                ),
            ],
          ),
          if (!shared && !done && !cancelled) ...[
            const SizedBox(height: 12),
            _AnimatedProgress(value: (item.percent / 100).clamp(0.0, 1.0)),
            const SizedBox(height: 10),
            Row(
              children: [
                Text(
                  '${TransferMetrics.formatSize(item.transferredBytes)} / '
                  '${TransferMetrics.formatSize(item.totalBytes)}',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
                const Spacer(),
                if (item.etaString.isNotEmpty)
                  Text(
                    '⏳ ${item.etaString.replaceAll(' remaining', '')}',
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              if (!item.incoming && !shared)
                const Expanded(
                  child: Text(
                    'Outgoing',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 11.5),
                  ),
                ),
              const Spacer(),
              if (!shared && !done && !cancelled && item.incoming)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: paused ? 'Resume' : 'Pause',
                  onPressed: () => controller.togglePause(item),
                  icon: Icon(
                    paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                    color: AppColors.warning,
                  ),
                ),
              if (!shared && !done && !cancelled && item.incoming)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Cancel',
                  onPressed: () => controller.cancelTransfer(item),
                  icon: const Icon(Icons.close_rounded, color: AppColors.danger),
                ),
              if (done)
                OutlinedButton.icon(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Opening file…')),
                    );
                  },
                  icon: const Icon(Icons.play_arrow_rounded, size: 16),
                  label: const Text('Open / Play'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  static String _statusLine(TransferItem item) {
    switch (item.status) {
      case TransferStatus.completed:
        return TransferMetrics.formatSize(item.totalBytes);
      case TransferStatus.cancelled:
        return 'Cancelled';
      case TransferStatus.shared:
        return 'Ready to send • ${TransferMetrics.formatSize(item.totalBytes)}';
      case TransferStatus.paused:
        return 'Paused';
      case TransferStatus.failed:
        return 'Failed';
      case TransferStatus.active:
        return item.incoming ? 'Receiving' : 'Sending';
    }
  }
}

class _AnimatedProgress extends StatelessWidget {
  const _AnimatedProgress({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value),
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
      builder: (context, v, _) => ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: LinearProgressIndicator(
          value: v,
          minHeight: 8,
          backgroundColor: AppColors.surfaceHigh,
          valueColor: const AlwaysStoppedAnimation(AppColors.primary),
        ),
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.onSend,
    required this.onAttach,
  });

  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback onAttach;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Attach files',
            onPressed: onAttach,
            icon: const Icon(Icons.attach_file_rounded, color: AppColors.accent),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: const InputDecoration(
                hintText: 'Type a message…',
                contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            tooltip: 'Send',
            onPressed: onSend,
            style: IconButton.styleFrom(backgroundColor: AppColors.primary),
            icon: const Icon(Icons.send_rounded, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

String _timeLabel(DateTime time) {
  final h = time.hour.toString().padLeft(2, '0');
  final m = time.minute.toString().padLeft(2, '0');
  return '$h:$m';
}

/// Thin wrapper so the session screen can pick more files mid-session.
class FilePickerBridge {
  FilePickerBridge._();

  static Future<List<SharedFile>> pick() async {
    try {
      final picked = await FilePicker.pickFiles();
      final out = <SharedFile>[];
      for (final f in picked) {
        final path = f.path;
        if (path == null || path.isEmpty) continue;
        out.add(SharedFile.fromPath(
          filePath: path,
          customName: f.name,
          customSize: f.lengthSync(),
          ownedByApp: false,
        ));
      }
      return out;
    } catch (_) {
      return const [];
    }
  }
}
