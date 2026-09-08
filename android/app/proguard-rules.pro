# Room generated database implementations are created through reflection.
# Keep their no-argument constructors so WorkManager can initialize in release builds.
-keep class * extends androidx.room.RoomDatabase {
    <init>();
}
