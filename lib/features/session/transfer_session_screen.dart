import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/platform/native_bridge.dart';
import '../../core/utils/transfer_metrics.dart';
import '../../state/share_controller.dart';
import '../../state/share_scope.dart';
import '../../theme/app_theme.dart';
import '../common/ui_kit.dart';
import '../picker/file_picker_screen.dart';

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

  /// 0 = chat feed, 1 = session files. Kept in the room so the toggle survives
  /// rebuilds triggered by incoming messages.
  int _view = 0;

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
    // The in-app picker, not the system file chooser: the system dialog sends
    // the user through Google Files and back, which is exactly the detour this
    // screen exists to avoid.
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FilePickerScreen(
          onConfirm: (files) {
            if (files.isEmpty) return;
            controller.shareFiles(files);
            _scrollToEnd();
          },
        ),
      ),
    );
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
                    // A joined device has no server of its own, so fall back to
                    // the address it dialled.
                    controller.serverUrl ??
                        controller.connectedPeerUrl ??
                        'Room not started',
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
          _ViewToggle(
            view: _view,
            onChanged: (v) => setState(() => _view = v),
          ),
          Expanded(
            child: _view == 0
                ? _buildChatFeed(entries)
                : _SessionFilesView(entries: entries),
          ),
          // The composer belongs to the chat view; showing it over a file list
          // would push the list up and hide rows behind the keyboard.
          if (_view == 0)
            _InputBar(
              controller: _textController,
              onSend: _sendText,
              onAttach: _attachFiles,
            ),
        ],
      ),
    );
  }

  Widget _buildChatFeed(List<Object> entries) {
    if (entries.isEmpty) {
      return const EmptyState(
        icon: Icons.forum_rounded,
        title: 'Room is quiet',
        subtitle: 'Send a message or attach files to start the session.',
      );
    }

    return ListView.builder(
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
    );
  }
}

/// Segmented control switching the room between chat and its file list.
class _ViewToggle extends StatelessWidget {
  const _ViewToggle({required this.view, required this.onChanged});

  final int view;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.background,
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            _ToggleTab(
              label: 'Live Chat',
              icon: Icons.forum_rounded,
              selected: view == 0,
              onTap: () => onChanged(0),
            ),
            _ToggleTab(
              label: 'Session Files',
              icon: Icons.folder_rounded,
              selected: view == 1,
              onTap: () => onChanged(1),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToggleTab extends StatelessWidget {
  const _ToggleTab({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primary.withValues(alpha: 0.22)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
              color: selected
                  ? AppColors.primary.withValues(alpha: 0.55)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 15,
                color: selected ? AppColors.primary : AppColors.textMuted,
              ),
              const SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(
                  color: selected ? AppColors.textPrimary : AppColors.textMuted,
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Every file that moved during this session, sendable or openable in place.
class _SessionFilesView extends StatelessWidget {
  const _SessionFilesView({required this.entries});

  final List<Object> entries;

  @override
  Widget build(BuildContext context) {
    final files = entries.whereType<TransferItem>().toList().reversed.toList();

    if (files.isEmpty) {
      return const EmptyState(
        icon: Icons.folder_open_rounded,
        title: 'No files in this session yet',
        subtitle: 'Files you send or receive in this room will be listed here.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 20),
      itemCount: files.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) => _SessionFileRow(item: files[i]),
    );
  }
}

class _SessionFileRow extends StatelessWidget {
  const _SessionFileRow({required this.item});

  final TransferItem item;

  @override
  Widget build(BuildContext context) {
    final ready = item.status == TransferStatus.completed ||
        item.status == TransferStatus.shared;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          CategoryAvatar(category: item.category, size: 38),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TruncatedName(name: item.fileName, maxLength: 28),
                const SizedBox(height: 3),
                Text(
                  '${item.incoming ? 'Received' : 'Sent'} • '
                  '${TransferMetrics.formatSize(item.totalBytes)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5),
                ),
              ],
            ),
          ),
          if (ready)
            IconButton(
              tooltip: 'Open',
              onPressed: () async {
                final path = item.filePath;
                final opened = path != null &&
                    await NativeBridge.openFile(path);
                if (!opened && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'No app can open ${item.fileName} on this device',
                      ),
                    ),
                  );
                }
              },
              icon: const Icon(
                Icons.open_in_new_rounded,
                size: 18,
                color: AppColors.accent,
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                '${item.percent.toStringAsFixed(0)}%',
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
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
