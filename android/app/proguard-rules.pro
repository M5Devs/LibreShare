# The Kotlin handlers are reached from Dart only through MethodChannel string
# dispatch, so R8 cannot see the call sites and may rename or strip them.
# Keep just these entry points; keeping all of io.flutter.** would defeat
# shrinking of the Flutter embedding and grow the dex substantially.
-keep class com.m5dev.libreshare.MainActivity { *; }
-keep class com.m5dev.libreshare.AppCatalogHandler { *; }
-keep class com.m5dev.libreshare.StorageInfoHandler { *; }
-keep class com.m5dev.libreshare.HotspotController { *; }
-keep class com.m5dev.libreshare.HotspotIpDetector { *; }
-keep class com.m5dev.libreshare.LibreShareService { *; }
-keep class com.m5dev.libreshare.NativeEvents { *; }
