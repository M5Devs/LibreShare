import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../app_routes.dart';
import '../../core/platform/app_catalog_bridge.dart';
import '../../core/server/shared_file.dart';
import '../../core/utils/permission_helper.dart';
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
  const FilePickerScreen({
    super.key,
    this.libraryLoader,
    this.appLoader,
    this.apkLoader,
  });

  /// Overridable for tests; defaults to a real device scan.
  final Future<MediaLibrary> Function()? libraryLoader;
  final Future<List<InstalledAppInfo>> Function()? appLoader;

  /// Scans storage for `.apk` files (the "Stored APKs" filter).
  final Future<List<MediaItem>> Function()? apkLoader;

  @override
  State<FilePickerScreen> createState() => _FilePickerScreenState();
}

class _FilePickerScreenState extends State<FilePickerScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  late final Future<MediaLibrary> Function() _libraryLoader;
  late final Future<List<InstalledAppInfo>> Function() _appLoader;
  late final Future<List<MediaItem>> Function() _apkLoader;

  MediaLibrary _library = MediaLibrary.empty;
  List<InstalledAppInfo> _apps = const [];
  List<MediaItem> _storedApks = const [];
  bool _loading = true;
  bool _storedApksOnly = false;

  final Set<String> _selectedPaths = {};
  final Map<String, PickableItem> _selectedItems = {};

  @override
  void initState() {
    super.initState();
    _libraryLoader = widget.libraryLoader ?? (() => MediaCatalog().scan());
    _appLoader = widget.appLoader ?? AppCatalogBridge.listInstalledApps;
    _apkLoader = widget.apkLoader ?? (() => MediaCatalog().scanApks());
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
    // Ask for media read access first: on Android 13+ a missing grant makes
    // MediaStore return only this app's own files, which reads as "0 photos".
    // Tests inject a loader, so they skip the platform prompt entirely.
    if (widget.libraryLoader == null && mounted) {
      await PermissionHelper.requestMediaPermissions(context);
      if (!mounted) return;
    }

    // Each source is settled independently: an unreadable media library must
    // not empty the Apps tab, and vice versa.
    final library = await _guard(_libraryLoader, MediaLibrary.empty);
    final apps = await _guard(_appLoader, const <InstalledAppInfo>[]);
    final apks = await _guard(_apkLoader, const <MediaItem>[]);

    if (!mounted) return;
    setState(() {
      _library = library;
      _apps = apps;
      _storedApks = apks;
      _loading = false;
    });
  }

  static Future<T> _guard<T>(Future<T> Function() load, T fallback) async {
    try {
      return await load();
    } catch (_) {
      return fallback;
    }
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
    final controller = ShareScope.of(context);
    // Sending nothing is a valid choice: the user may only want the room to
    // receive files or chat, which is how SHAREit behaves.
    if (_selectedItems.isNotEmpty) {
      controller.shareFiles(
        _selectedItems.values.map((e) => e.toSharedFile()).toList(),
      );
    }
    Navigator.of(context).pushNamed(AppRoutes.receive);
  }

  void _removeSelection(PickableItem item) {
    setState(() {
      _selectedPaths.remove(item.path);
      _selectedItems.remove(item.path);
    });
  }

  /// Opens the review drawer listing every pick across all five tabs.
  Future<void> _reviewSelection() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _SelectionDrawer(
        items: _selectedItems.values.toList(),
        onRemove: _removeSelection,
        onSend: () {
          Navigator.of(ctx).pop();
          _proceed();
        },
      ),
    );
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
                        storedApks: _storedApks,
                        storedApksOnly: _storedApksOnly,
                        onFilterChanged: (v) => setState(() => _storedApksOnly = v),
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
                  onTap: _reviewSelection,
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
    required this.storedApks,
    required this.storedApksOnly,
    required this.onFilterChanged,
    required this.selectedPaths,
    required this.onToggle,
  });

  final List<InstalledAppInfo> apps;
  final List<MediaItem> storedApks;
  final bool storedApksOnly;
  final ValueChanged<bool> onFilterChanged;
  final Set<String> selectedPaths;
  final void Function(PickableItem) onToggle;

  @override
  Widget build(BuildContext context) {
    final installed = apps
        .map((a) => PickableItem(
              name: '${a.label}.apk',
              path: a.apkPath,
              sizeBytes: a.sizeBytes,
              category: 'Apps',
              subtitle: a.packageName,
              iconBytes: a.iconBytes,
            ))
        .toList();

    final stored = storedApks
        .map((m) => PickableItem(
              name: m.name,
              path: m.path,
              sizeBytes: m.sizeBytes,
              category: 'Apps',
              subtitle: 'Stored APK',
            ))
        .toList();

    final items = storedApksOnly ? stored : installed;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: SegmentedButton<bool>(
            segments: [
              ButtonSegment(value: false, label: Text('Installed (${installed.length})')),
              ButtonSegment(value: true, label: Text('Stored APKs (${stored.length})')),
            ],
            selected: {storedApksOnly},
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
              ? EmptyState(
                  icon: storedApksOnly
                      ? Icons.folder_off_rounded
                      : Icons.android_rounded,
                  title: storedApksOnly
                      ? 'No stored APKs found'
                      : 'No apps found',
                  subtitle: storedApksOnly
                      ? 'Downloaded .apk files on this device appear here.'
                      : 'Installed apps will appear here once the app catalog loads.',
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
    required this.onTap,
    required this.onSend,
  });

  final int count;
  final int totalBytes;
  final VoidCallback onTap;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final hasSelection = count > 0;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 16),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Material(
              color: hasSelection
                  ? AppColors.primary.withValues(alpha: 0.12)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                onTap: hasSelection ? onTap : null,
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    children: [
                      Icon(
                        hasSelection
                            ? Icons.unfold_more_rounded
                            : Icons.checklist_rounded,
                        size: 18,
                        color: hasSelection ? AppColors.primary : AppColors.textMuted,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              hasSelection
                                  ? '$count file${count == 1 ? '' : 's'} selected'
                                  : 'Nothing selected',
                              style: TextStyle(
                                color: hasSelection
                                    ? AppColors.textPrimary
                                    : AppColors.textMuted,
                                fontWeight: FontWeight.w700,
                                fontSize: 13.5,
                              ),
                            ),
                            const SizedBox(height: 1),
                            Text(
                              hasSelection
                                  ? '${TransferMetrics.formatSize(totalBytes)} • tap to review'
                                  : 'Tap Next to just open the room',
                              style: const TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 11.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Always enabled: an empty selection still opens the room so the
          // user can receive or chat, which is the SHAREit behaviour.
          ElevatedButton.icon(
            onPressed: onSend,
            icon: const Icon(Icons.arrow_forward_rounded, size: 18),
            label: const Text('Next'),
          ),
        ],
      ),
    );
  }
}

/// Expandable review of every selection, across all picker tabs.
class _SelectionDrawer extends StatefulWidget {
  const _SelectionDrawer({
    required this.items,
    required this.onRemove,
    required this.onSend,
  });

  final List<PickableItem> items;
  final void Function(PickableItem) onRemove;
  final VoidCallback onSend;

  @override
  State<_SelectionDrawer> createState() => _SelectionDrawerState();
}

class _SelectionDrawerState extends State<_SelectionDrawer> {
  /// The sheet sits on its own route, so parent rebuilds do not reach it.
  /// Removals are applied here and mirrored to the picker via [onRemove].
  late List<PickableItem> _items = List.of(widget.items);

  int get _totalBytes => _items.fold(0, (sum, item) => sum + item.sizeBytes);

  void _remove(PickableItem item) {
    setState(() => _items = _items.where((e) => e.path != item.path).toList());
    widget.onRemove(item);
    // An empty review list has nothing left to show, so close it and let the
    // picker's own empty state take over.
    if (_items.isEmpty) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height;

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: height * 0.72),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.textMuted,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Review selection',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${_items.length} item${_items.length == 1 ? '' : 's'} • '
                          '${TransferMetrics.formatSize(_totalBytes)}',
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: widget.onSend,
                    child: const Text('Send →'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 16),
                itemCount: _items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final item = _items[i];
                  return Container(
                    padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceHigh,
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      children: [
                        CategoryAvatar(category: item.category, size: 34),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${item.category} • ${TransferMetrics.formatSize(item.sizeBytes)}',
                                style: const TextStyle(
                                  color: AppColors.textMuted,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Remove ${item.name}',
                          onPressed: () => _remove(item),
                          icon: const Icon(
                            Icons.remove_circle_rounded,
                            color: AppColors.danger,
                            size: 20,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
