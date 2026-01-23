# Flutter-specific rules.
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.plugins.firebase.core.** { *; }

# Firebase rules
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-keep class com.google.android.gms.common.** { *; }
-keepnames class com.google.android.gms.common.api.CommonStatusCodes
-keepnames class com.google.android.gms.common.api.Status
-keep class com.google.firebase.auth.** { *; }
-keep class com.google.firebase.firestore.** { *; }
-keep public class com.google.android.gms.common.api.Status { *; }

# For cloud_firestore
-keep class com.google.protobuf.** { *; }

# For flutter_background_service
-keep class id.flutter.flutter_background_service.** { *; }

# For audioplayers
-keep class io.flutter.plugins.audioplayers.** { *; }

# For vibration
-keep class io.flutter.plugins.vibration.** { *; }

# ✅ --- FIX FOR R8 ERROR ---
# 1. Tell R8 to ignore warnings if these classes are missing
-dontwarn com.google.android.play.core.splitcompat.**
-dontwarn com.google.android.play.core.splitinstall.**
-dontwarn com.google.android.play.core.tasks.**
-dontwarn com.google.android.play.core.**

# 2. Keep them if they actually exist (safe to leave included)
-keep class com.google.android.play.core.splitcompat.** { *; }
-keep class com.google.android.play.core.splitinstall.** { *; }
-keep class com.google.android.play.core.tasks.** { *; }