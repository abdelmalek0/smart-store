# JavaCPP ProGuard rules
-dontwarn java.lang.management.**
-dontwarn javax.management.**
-keep class org.bytedeco.javacpp.** { *; }
-keep class org.bytedeco.javacv.** { *; }
-keep class org.bytedeco.ffmpeg.** { *; }
-keepclassmembers class org.bytedeco.** {
    *;
}
-dontwarn org.apache.maven.**
-dontwarn org.bytedeco.javacpp.**
-dontwarn com.jogamp.**
-dontwarn java.awt.**
-dontwarn javax.swing.**
-dontwarn javafx.**
-dontwarn javax.imageio.**
-dontwarn java.beans.**
