# xlog_plugin — consumer ProGuard/R8 rules.
#
# These are applied automatically to any app that depends on this plugin
# (via `consumerProguardFiles` in android/build.gradle), so integrators do not
# normally need to add anything themselves.
#
# Why these are required:
# The native library (libmarsxlog.so) reaches back into the Java/Kotlin layer
# through JNI using *exact* class, method and field names. If R8/ProGuard
# renames or strips them, JNI lookups fail at runtime (UnsatisfiedLinkError, or
# silently wrong config because a field id can't be resolved). So the mars glue
# classes must be kept verbatim.

# mars-xlog glue (native methods + XLogConfig/XLoggerInfo fields read via JNI).
-keep class com.tencent.mars.xlog.** { *; }
-keepclassmembers class com.tencent.mars.xlog.** { *; }

# Keep all native method signatures (defensive; covered by the rule above too).
-keepclasseswithmembernames class com.tencent.mars.xlog.** {
    native <methods>;
}

# Flutter plugin entry point (instantiated by the generated plugin registrant).
-keep class com.youfi.xlog_plugin.** { *; }
