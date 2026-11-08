# App-specific R8 rules. The libraries in use ship their own consumer rules.

# WorkManager loads its Room database by reflection (Class.getConstructor().newInstance()).
# R8 full mode (AGP 9) strips the generated class's no-arg constructor, which crashed release
# builds with NoSuchMethodException at WorkDatabase_Impl (FOX-187).
-keep class androidx.work.impl.WorkDatabase_Impl { <init>(); }
-keep class * extends androidx.room.RoomDatabase { <init>(); }
