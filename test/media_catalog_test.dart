import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:libreshare/features/picker/media_catalog.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('media_catalog_test_');
  });

  tearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  Future<File> writeFile(String relative, {int bytes = 16}) async {
    final file = File('${root.path}/$relative');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(List<int>.filled(bytes, 0x41));
    return file;
  }

  test('extensionOf handles names, dotfiles and extensionless files', () {
    expect(MediaCatalog.extensionOf('movie.MP4'), 'mp4');
    expect(MediaCatalog.extensionOf('archive.tar.gz'), 'gz');
    expect(MediaCatalog.extensionOf('README'), '');
    expect(MediaCatalog.extensionOf('.gitignore'), '');
    expect(MediaCatalog.extensionOf('trailing.'), '');
  });

  test('scan classifies files into the right categories', () async {
    await writeFile('Pictures/holiday.jpg');
    await writeFile('Pictures/nested/deeper/portrait.PNG');
    await writeFile('Movies/clip.mp4');
    await writeFile('Music/song.mp3');
    await writeFile('Docs/report.pdf');
    await writeFile('Docs/unknown.xyz');

    final library = await MediaCatalog(rootDirectories: [root.path]).scan();

    expect(library.photos.map((e) => e.name), containsAll(['holiday.jpg', 'portrait.PNG']));
    expect(library.videos.single.name, 'clip.mp4');
    expect(library.music.single.name, 'song.mp3');
    expect(library.documents.single.name, 'report.pdf');
    expect(library.totalCount, 5);
  });

  test('scan routes .apk files into the apps category, not documents', () async {
    await writeFile('Download/Telegram.apk', bytes: 128);
    await writeFile('Docs/report.pdf');

    final library = await MediaCatalog(rootDirectories: [root.path]).scan();

    expect(library.apks.single.name, 'Telegram.apk');
    expect(library.apks.single.sizeBytes, 128);
    expect(library.documents.map((e) => e.name), isNot(contains('Telegram.apk')));
    expect(library.totalCount, 2);
  });

  test('scanApks finds stored APKs and sorts newest first', () async {
    final older = await writeFile('Download/older.apk', bytes: 64);
    final newer = await writeFile('Download/nested/newer.apk', bytes: 64);
    await older.setLastModified(DateTime(2020, 1, 1));
    await newer.setLastModified(DateTime(2024, 1, 1));

    final apks = await MediaCatalog(rootDirectories: [root.path]).scanApks();

    expect(apks.map((e) => e.name), ['newer.apk', 'older.apk']);
  });

  test('scanApks ignores non-apk files', () async {
    await writeFile('Download/notes.txt');
    await writeFile('Download/app.apk');
    final apks = await MediaCatalog(rootDirectories: [root.path]).scanApks();
    expect(apks.single.name, 'app.apk');
  });

  test('scan records byte sizes', () async {
    await writeFile('Music/sized.wav', bytes: 512);
    final library = await MediaCatalog(rootDirectories: [root.path]).scan();
    expect(library.music.single.sizeBytes, 512);
  });

  test('scan returns empty library for a missing root', () async {
    final library = await MediaCatalog(
      rootDirectories: ['${root.path}/does_not_exist'],
    ).scan();
    expect(library.totalCount, 0);
    expect(MediaLibrary.empty.totalCount, 0);
  });

  test('scan does not recurse without bound', () async {
    var path = root.path;
    for (var i = 0; i < 10; i++) {
      path = '$path/level$i';
    }
    await writeFile('${path.substring(root.path.length + 1)}/deep.mp3');

    final library = await MediaCatalog(rootDirectories: [root.path]).scan();
    expect(library.music, isEmpty);
  });
}
