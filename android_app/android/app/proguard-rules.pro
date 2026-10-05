# Chip reading (NfcBridge): BouncyCastle and JMRTD find their classes by name.
-keep class org.bouncycastle.** { *; }
-keep class org.jmrtd.** { *; }
-keep class net.sf.scuba.** { *; }
-keep class org.ejbca.** { *; }
# Tesseract's native code calls back into these.
-keep class com.googlecode.tesseract.android.** { *; }
-keep class com.googlecode.leptonica.android.** { *; }
-dontwarn org.bouncycastle.**
-dontwarn org.jmrtd.**
-dontwarn net.sf.scuba.**
-dontwarn org.ejbca.**
-dontwarn javax.naming.**
