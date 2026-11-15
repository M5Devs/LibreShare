import 'package:flutter/material.dart';

import '../../core/platform/storage_bridge.dart';
import '../../core/server/shared_file.dart';
import '../../core/utils/transfer_metrics.dart';
import '../../state/share_scope.dart';
import '../../theme/app_theme.dart';
import '../common/ui_kit.dart';
import '../picker/media_catalog.dart';

/// Storage overview plus the list of received files.
class FilesScreen extends StatefulWidget {
  const FilesScreen({super.key, this.libraryLoader, this.storageInfoLoader});

  /// Overridable for tests; defaults to real device scans.
  final Future<MediaLibrary> Function()? libraryLoader;
  final Future<StorageInfo?> Function()? storageInfoLoader;

  @override
  State<FilesScreen> createState() => _FilesScreenState();
}

class _FilesScreenState extends State<FilesScreen> {
  StorageInfo? _storage;
  MediaLibrary _library = MediaLibrary.empty;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final libraryLoader = widget.libraryLoader ?? (() => MediaCatalog().scan());
    final storageLoader = widget.storageInfoLoader ?? StorageBridge.getStorageInfo;
    final results = await Future.wait([
      storageLoader(),
      libraryLoader(),
    ]);

    if (!mounted) return;
    setState(() {
      _storage = results[0] as StorageInfo?;
      _library = results[1] as MediaLibrary;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = ShareScope.of(context);
    final received = controller.storage.receivedFiles.reversed.toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Files & Storage', style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(18, 6, 18, 28),
              children: [
                _StorageBar(storage: _storage),
                const SizedBox(height: 18),
                const SectionHeader(title: 'Categories'),
                const SizedBox(height: 12),
                _CategoryGrid(library: _library),
                const SizedBox(height: 22),
                SectionHeader(
                  title: 'Received Files',
                  trailing: Text(
                    '${received.length} item${received.length == 1 ? '' : 's'}',
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5),
                  ),
                ),
                const SizedBox(height: 12),
                if (received.isEmpty)
                  const EmptyState(
                    icon: Icons.download_done_rounded,
                    title: 'No files received yet',
                    subtitle: 'Files sent to this device land in Download/LibreShare/.',
                  )
                else
                  for (final file in received)
                    _ReceivedTile(
                      file: file,
                      onDelete: () => controller.removeReceivedFile(file.id),
                    ),
              ],
            ),
    );
  }
}

class _StorageBar extends StatelessWidget {
  const _StorageBar({required this.storage});

  final StorageInfo? storage;

  @override
  Widget build(BuildContext context) {
    final info = storage;
    final fraction = (info != null && info.totalBytes > 0)
        ? (info.usedBytes / info.totalBytes).clamp(0.0, 1.0)
        : 0.0;

    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.storage_rounded, color: AppColors.accent, size: 20),
              SizedBox(width: 8),
              Text(
                'Device Storage',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 10,
              backgroundColor: AppColors.surfaceHigh,
              valueColor: const AlwaysStoppedAnimation(AppColors.accent),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            info == null
                ? 'Storage details unavailable on this platform'
                : '${TransferMetrics.formatSize(info.usedBytes)} used of '
                    '${TransferMetrics.formatSize(info.totalBytes)}',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
          ),
        ],
      ),
    );
  }
}

class _CategoryGrid extends StatelessWidget {
  const _CategoryGrid({required this.library});

  final MediaLibrary library;

  @override
  Widget build(BuildContext context) {
    final tiles = [
      _CatTile('Videos', Icons.movie_rounded, library.videos.length, AppColors.primary),
      _CatTile('Photos', Icons.photo_rounded, library.photos.length, AppColors.accent),
      _CatTile('Apps', Icons.android_rounded, library.documents.length, AppColors.success),
      _CatTile('Audio', Icons.music_note_rounded, library.music.length, AppColors.warning),
      _CatTile('Docs', Icons.description_rounded, library.documents.length, const Color(0xFF60A5FA)),
    ];

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 2.4,
      children: [
        for (final t in tiles)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Icon(t.icon, color: t.color, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        t.label,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 13.5,
                        ),
                      ),
                      Text(
                        '${t.count} file${t.count == 1 ? '' : 's'}',
                        style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _CatTile {
  const _CatTile(this.label, this.icon, this.count, this.color);

  final String label;
  final IconData icon;
  final int count;
  final Color color;
}

class _ReceivedTile extends StatelessWidget {
  const _ReceivedTile({required this.file, required this.onDelete});

  final SharedFile file;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final controller = ShareScope.of(context);
    final category = controller.storage.getCategoryForFilename(file.name);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          CategoryAvatar(category: category),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TruncatedName(name: file.name, maxLength: 26),
                const SizedBox(height: 3),
                Text(
                  '${TransferMetrics.formatSize(file.size)} • ${_folder(file.filePath)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Open',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Opening file…')),
              );
            },
            icon: const Icon(Icons.open_in_new_rounded, size: 18, color: AppColors.accent),
          ),
          IconButton(
            tooltip: 'Delete',
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.danger),
          ),
        ],
      ),
    );
  }

  static String _folder(String path) {
    final idx = path.indexOf('Download/LibreShare');
    if (idx != -1) return path.substring(idx);
    final libre = path.indexOf('LibreShare');
    if (libre != -1) return 'Download/${path.substring(libre)}';
    return path;
  }
}
