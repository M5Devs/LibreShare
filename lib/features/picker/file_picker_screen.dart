import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../app_routes.dart';
import '../../core/platform/app_catalog_bridge.dart';
import '../../core/server/shared_file.dart';
import '../../core/utils/transfer_metrics.dart';
import '../../state/share_scope.dart';
import '../../theme/app_theme.dart';
import '../common/ui_kit.dart';
import 'media_catalog.dart';

/// A selectable entry in the picker. Wraps either a device media file or an
/// installed app's APK.
class PickableItem {
  const PickableItem({
    required this.name,
    required this.path,
    required this.sizeBytes,
    required this.category,
    this.subtitle,
    this.iconBytes,
  });

  final String name;
  final String path;
  final int sizeBytes;
  final String category;
  final String? subtitle;
  final List<int>? iconBytes;

  SharedFile toSharedFile() => SharedFile.fromPath(
        filePath: path,
        customName: name,
        customSize: sizeBytes,
        ownedByApp: false,
      );
}

class FilePickerScreen extends StatefulWidget {
  const FilePickerScreen({super.key, this.libraryLoader, this.appLoader});

  /// Overridable for tests; defaults to a real device scan.
  final Future<MediaLibrary> Function()? libraryLoader;
  final Future<List<InstalledAppInfo>> Function()? appLoader;

  @override
  State<FilePickerScreen> createState() => _FilePickerScreenState();
}

class _FilePickerScreenState extends State<FilePickerScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  late final Future<MediaLibrary> Function() _libraryLoader;
  late final Future<List<InstalledAppInfo>> Function() _appLoader;

  MediaLibrary _library = MediaLibrary.empty;
  List<InstalledAppInfo> _apps = const [];
  bool _loading = true;
  bool _appsOnly = false;

  final Set<String> _selectedPaths = {};
  final Map<String, PickableItem> _selectedItems = {};

  @override
  void initState() {
    super.initState();
    _libraryLoader = widget.libraryLoader ?? (() => MediaCatalog().scan());
    _appLoader = widget.appLoader ?? AppCatalogBridge.listInstalledApps;
    _tabs = TabController(length: 5, vsync: this);
    _tabs.addListener(() {
      if (mounted) setState(() {});
    });
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      _libraryLoader(),
      _appLoader(),
    ]);
    if (!mounted) return;
    setState(() {
      _library = results[0] as MediaLibrary;
      _apps = results[1] as List<InstalledAppInfo>;
      _loading = false;
    });
  }

  void _toggle(PickableItem item) {
    setState(() {
      if (_selectedPaths.contains(item.path)) {
        _selectedPaths.remove(item.path);
        _selectedItems.remove(item.path);
      } else {
        _selectedPaths.add(item.path);
        _selectedItems[item.path] = item;
      }
    });
  }

  int get _totalBytes =>
      _selectedItems.values.fold(0, (sum, item) => sum + item.sizeBytes);

  void _proceed() {
    if (_selectedItems.isEmpty) return;
    final controller = ShareScope.of(context);
    controller.shareFiles(
      _selectedItems.values.map((e) => e.toSharedFile()).toList(),
    );
    Navigator.of(context).pushNamed(AppRoutes.receive);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Send Files',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(text: 'Apps 📦'),
            Tab(text: 'Photos 📸'),
            Tab(text: 'Videos 🎬'),
            Tab(text: 'Music 🎵'),
            Tab(text: 'Files 📄'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: TabBarView(
                    controller: _tabs,
                    children: [
                      _AppsTab(
                        apps: _apps,
                        appsOnly: _appsOnly,
                        onFilterChanged: (v) => setState(() => _appsOnly = v),
                        selectedPaths: _selectedPaths,
                        onToggle: _toggle,
                      ),
                      _MediaGridTab(
                        items: _photoItems,
                        selectedPaths: _selectedPaths,
                        onToggle: _toggle,
                      ),
                      _MediaGridTab(
                        items: _videoItems,
                        selectedPaths: _selectedPaths,
                        onToggle: _toggle,
                      ),
                      _MediaListTab(
                        items: _musicItems,
                        selectedPaths: _selectedPaths,
                        onToggle: _toggle,
                      ),
                      _MediaListTab(
                        items: _documentItems,
                        selectedPaths: _selectedPaths,
                        onToggle: _toggle,
                      ),
                    ],
                  ),
                ),
                _SelectionBar(
                  count: _selectedItems.length,
                  totalBytes: _totalBytes,
                  onSend: _proceed,
                ),
              ],
            ),
    );
  }

  List<PickableItem> get _photoItems => _library.photos
      .map((m) => PickableItem(
            name: m.name,
            path: m.path,
            sizeBytes: m.sizeBytes,
            category: 'Images',
          ))
      .toList();

  List<PickableItem> get _videoItems => _library.videos
      .map((m) => PickableItem(
            name: m.name,
            path: m.path,
            sizeBytes: m.sizeBytes,
            category: 'Videos',
          ))
      .toList();

  List<PickableItem> get _musicItems => _library.music
      .map((m) => PickableItem(
            name: m.name,
            path: m.path,
            sizeBytes: m.sizeBytes,
            category: 'Audio',
            subtitle: m.sizeLabel,
          ))
      .toList();

  List<PickableItem> get _documentItems => _library.documents
      .map((m) => PickableItem(
            name: m.name,
            path: m.path,
            sizeBytes: m.sizeBytes,
            category: 'Documents',
            subtitle: m.sizeLabel,
          ))
      .toList();
}

class _AppsTab extends StatelessWidget {
  const _AppsTab({
    required this.apps,
    required this.appsOnly,
    required this.onFilterChanged,
    required this.selectedPaths,
    required this.onToggle,
  });

  final List<InstalledAppInfo> apps;
  final bool appsOnly;
  final ValueChanged<bool> onFilterChanged;
  final Set<String> selectedPaths;
  final void Function(PickableItem) onToggle;

  @override
  Widget build(BuildContext context) {
    final items = apps
        .map((a) => PickableItem(
              name: '${a.label}.apk',
              path: a.apkPath,
              sizeBytes: a.sizeBytes,
              category: 'Apps',
              subtitle: a.packageName,
              iconBytes: a.iconBytes,
            ))
        .toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Installed')),
              ButtonSegment(value: true, label: Text('Stored APKs')),
            ],
            selected: {appsOnly},
            onSelectionChanged: (s) => onFilterChanged(s.first),
            style: ButtonStyle(
              backgroundColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? AppColors.primary.withValues(alpha: 0.25)
                    : AppColors.surfaceHigh,
              ),
            ),
          ),
        ),
        Expanded(
          child: items.isEmpty
              ? const EmptyState(
                  icon: Icons.android_rounded,
                  title: 'No apps found',
                  subtitle: 'App extraction needs the Android app-listing helper.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final item = items[i];
                    return _SelectableRow(
                      item: item,
                      selected: selectedPaths.contains(item.path),
                      onToggle: () => onToggle(item),
                      leading: _AppIcon(bytes: item.iconBytes),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _AppIcon extends StatelessWidget {
  const _AppIcon({this.bytes});

  final List<int>? bytes;

  @override
  Widget build(BuildContext context) {
    if (bytes != null && bytes!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.memory(
          Uint8List.fromList(bytes!),
          width: 42,
          height: 42,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => const CategoryAvatar(category: 'Apps'),
        ),
      );
    }
    return const CategoryAvatar(category: 'Apps');
  }
}

class _MediaGridTab extends StatelessWidget {
  const _MediaGridTab({
    required this.items,
    required this.selectedPaths,
    required this.onToggle,
  });

  final List<PickableItem> items;
  final Set<String> selectedPaths;
  final void Function(PickableItem) onToggle;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const EmptyState(
        icon: Icons.image_not_supported_rounded,
        title: 'Nothing here yet',
        subtitle: 'Media found on this device will appear here.',
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 0.82,
      ),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final item = items[i];
        final selected = selectedPaths.contains(item.path);
        return GestureDetector(
          onTap: () => onToggle(item),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected ? AppColors.primary : AppColors.border,
                width: selected ? 2 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ClipRRect(
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
                        child: _Thumbnail(path: item.path, category: item.category),
                      ),
                      Positioned(
                        top: 6,
                        right: 6,
                        child: _CheckBubble(selected: selected),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        TransferMetrics.formatSize(item.sizeBytes),
                        style: const TextStyle(color: AppColors.textMuted, fontSize: 10.5),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.path, required this.category});

  final String path;
  final String category;

  @override
  Widget build(BuildContext context) {
    if (category == 'Images') {
      return Image.file(
        File(path),
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => const _ThumbFallback(),
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        const _ThumbFallback(),
        Center(
          child: Icon(
            Icons.play_circle_fill_rounded,
            color: Colors.white.withValues(alpha: 0.85),
            size: 34,
          ),
        ),
      ],
    );
  }
}

class _ThumbFallback extends StatelessWidget {
  const _ThumbFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surfaceHigh,
      alignment: Alignment.center,
      child: const Icon(Icons.image_rounded, color: AppColors.textMuted),
    );
  }
}

class _MediaListTab extends StatelessWidget {
  const _MediaListTab({
    required this.items,
    required this.selectedPaths,
    required this.onToggle,
  });

  final List<PickableItem> items;
  final Set<String> selectedPaths;
  final void Function(PickableItem) onToggle;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const EmptyState(
        icon: Icons.folder_off_rounded,
        title: 'No files found',
        subtitle: 'Documents and audio on this device will appear here.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final item = items[i];
        return _SelectableRow(
          item: item,
          selected: selectedPaths.contains(item.path),
          onToggle: () => onToggle(item),
          leading: CategoryAvatar(category: item.category),
        );
      },
    );
  }
}

class _SelectableRow extends StatelessWidget {
  const _SelectableRow({
    required this.item,
    required this.selected,
    required this.onToggle,
    required this.leading,
  });

  final PickableItem item;
  final bool selected;
  final VoidCallback onToggle;
  final Widget leading;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.border,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Row(
            children: [
              leading,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TruncatedName(name: item.name, maxLength: 26),
                    const SizedBox(height: 3),
                    Text(
                      item.subtitle ?? TransferMetrics.formatSize(item.sizeBytes),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _CheckBubble(selected: selected),
            ],
          ),
        ),
      ),
    );
  }
}

class _CheckBubble extends StatelessWidget {
  const _CheckBubble({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? AppColors.primary : Colors.black.withValues(alpha: 0.35),
        border: Border.all(
          color: selected ? AppColors.primary : Colors.white54,
          width: 1.6,
        ),
      ),
      child: selected
          ? const Icon(Icons.check_rounded, size: 16, color: Colors.white)
          : null,
    );
  }
}

class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.count,
    required this.totalBytes,
    required this.onSend,
  });

  final int count;
  final int totalBytes;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final enabled = count > 0;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  count == 0
                      ? 'Select files to send'
                      : 'Selected $count file${count == 1 ? '' : 's'}',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                if (count > 0)
                  Text(
                    'Total: ${TransferMetrics.formatSize(totalBytes)}',
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                  ),
              ],
            ),
          ),
          ElevatedButton.icon(
            onPressed: enabled ? onSend : null,
            icon: const Icon(Icons.arrow_forward_rounded, size: 18),
            label: const Text('Next / Send'),
            style: ElevatedButton.styleFrom(
              backgroundColor: enabled ? AppColors.primary : AppColors.surfaceHigh,
              foregroundColor: enabled ? Colors.white : AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}
