# Building for Android

Follow Godot's official page "Exporting for Android" for your exact Godot version; it
lists the required Android SDK / JDK versions. Summary:

1. Install **JDK 17** and the **Android SDK command-line tools**
   (`sdkmanager` packages: platform-tools, a build-tools version and platform listed in the Godot docs).
2. In Godot: **Editor > Manage Export Templates > Download and Install**.
3. Create a debug keystore (from Godot's docs):
   ```
   keytool -keyalg RSA -genkeypair -alias androiddebugkey -keypass android -keystore debug.keystore -storepass android -dname "CN=Android Debug,O=Android,C=US" -validity 9999 -deststoretype pkcs12
   ```
4. **Editor > Editor Settings > Export > Android**: set Android SDK Path, Java SDK Path,
   Debug Keystore (+ user `androiddebugkey`, password `android`).
5. **Project > Export**: an "Android Debug" preset is included. If Godot reports it as
   invalid, delete it and use *Add... > Android*; set package name (e.g. `com.yourname.swarajya`),
   enable arm64-v8a, leave "Use Gradle Build" off.
6. `mkdir build`, then export, or from the command line:
   ```
   godot --headless --path . --export-debug "Android Debug" build/swarajya-debug.apk
   adb install -r build/swarajya-debug.apk
   ```
7. Enable USB debugging on the phone, or copy the APK over and install it.

Release builds need your own release keystore. Never commit keystores (see `.gitignore`).
