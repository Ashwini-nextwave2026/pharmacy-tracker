# Google ML Kit text recognition: the plugin can also use the Chinese,
# Devanagari, Japanese and Korean readers, but we only include the Latin
# one (English bills). Tell R8 not to look for the others.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
