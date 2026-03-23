# 🔍 Google Sign-In Error 10 - Troubleshooting & Solutions

## ❌ Current Error
```
Google 登入平台錯誤: sign_in_failed - com.google.android.gms.common.api.ApiException: 10:
```

**Error 10 = Signature mismatch** - The SHA-1 fingerprint of the APK doesn't match what's registered in Google Cloud Console.

---

## 🔍 Root Cause Analysis

### Why This Happens
When you run `flutter run`, it builds the APK with **your local debug keystore**. This keystore has a unique SHA-1 fingerprint. Google Cloud Console checks if that SHA-1 is in its database. If not, it returns Error 10.

### Current Situation
- ✅ You have a debug keystore (created automatically by Android)
- ✅ The APK is signed with it
- ⏳ But the SHA-1 is NOT in Google Cloud Console yet

### The SHA-1 We Calculated
Based on the production keystore, the debug SHA-1 should be:
```
15:E7:03:09:80:64:C5:A2:1F:AB:AF:A4:03:A2:21:F3:65:AA:AC:B0
```

**But we need to VERIFY this is actually your current debug SHA-1.**

---

## 🛠️ Solution 1: Verify Your ACTUAL Debug SHA-1 (Recommended First)

### Step 1: Find Android SDK Location
```cmd
cd d:\project\golf\golf-score_app_1
flutter config --android-sdk
```

This will output something like:
```
C:\Users\YourUsername\AppData\Local\Android\sdk
```

### Step 2: Get Your ACTUAL Debug SHA-1
```cmd
keytool -list -v -keystore "%USERPROFILE%\.android\debug.keystore" -alias androiddebugkey -storepass android -keypass android | findstr "SHA1"
```

**Important**: Run this command and tell me the exact SHA-1 it outputs.

The output will look like:
```
SHA1: XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX
```

### Step 3: Copy This SHA-1
Copy the exact SHA-1 from the output above.

### Step 4: Add to Google Cloud Console
1. Go to: https://console.cloud.google.com/apis/credentials
2. Find your Android Client ID
3. Click on it
4. Find the "Add SHA-1" or "Edit" button
5. **Paste the SHA-1 from Step 2** (not the one we calculated)
6. Click "Save"
7. Wait 5-10 minutes
8. Test again: `flutter clean && flutter run`

---

## 🛠️ Solution 2: If keytool Command Doesn't Work

### Option A: Use Gradle to Get the SHA-1
```cmd
cd d:\project\golf\golf-score_app_1\android
gradlew signingReport
```

Look for output like:
```
Variant: debugAndroidTest
SHA1: XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX
```

Copy the SHA1 value and add it to Google Cloud.

### Option B: Extract SHA-1 from the Built APK
```cmd
cd d:\project\golf\golf-score_app_1
flutter build apk --release
keytool -printcert -jarfile build/app/outputs/apk/release/app-release.apk | findstr "SHA1"
```

### Option C: Use Android Studio
1. Open Android Studio
2. Go to: **Build** → **Generate Signed Bundle / APK**
3. Select **APK**
4. Click **Next**
5. Under "Key store path", browse to: `%USERPROFILE%\.android\debug.keystore`
6. Enter password: `android`
7. Key alias: `androiddebugkey`
8. Key password: `android`
9. Click **Next** and you'll see the SHA-1 fingerprints displayed!

---

## 🛠️ Solution 3: Nuclear Reset (If Nothing Else Works)

### Step 1: Delete Debug Keystore
```cmd
del "%USERPROFILE%\.android\debug.keystore"
```

### Step 2: Create New Debug Keystore
```cmd
keytool -genkey -v -keystore "%USERPROFILE%\.android\debug.keystore" -keyalg RSA -keysize 2048 -validity 10000 -alias androiddebugkey -storepass android -keypass android -dname "CN=Android Debug,O=Android,C=US"
```

### Step 3: Get NEW SHA-1
```cmd
keytool -list -v -keystore "%USERPROFILE%\.android\debug.keystore" -alias androiddebugkey -storepass android -keypass android | findstr "SHA1"
```

### Step 4: Add NEW SHA-1 to Google Cloud Console
1. Go to: https://console.cloud.google.com/apis/credentials
2. Delete the old Android Client ID
3. Click "+ CREATE CREDENTIALS"
4. Choose "OAuth client ID" → "Android"
5. Package name: `com.example.golf_score_app`
6. SHA-1: Paste the new SHA-1 from Step 3
7. Create it
8. Test: `flutter clean && flutter run`

---

## ✅ Verification Checklist

Before testing again, verify:

### In Google Cloud Console
- [ ] Android Client ID exists
- [ ] Package name is `com.example.golf_score_app`
- [ ] At least one SHA-1 fingerprint is listed
- [ ] The SHA-1 matches your actual debug keystore

### In Your Project
- [ ] `android/app/build.gradle.kts` has correct namespace
- [ ] `android/app/google-services.json` exists
- [ ] `pubspec.yaml` has google_sign_in plugin
- [ ] No compilation errors: `flutter analyze`

### On Your Device
- [ ] App is installed (same version as what you're about to build)
- [ ] Device has internet connection
- [ ] Google Play Services is up to date

---

## 🧪 Testing After Adding SHA-1

```cmd
cd d:\project\golf\golf-score_app_1

# Clean everything
flutter clean
rm -r build/

# Get dependencies
flutter pub get

# Build and run
flutter run
```

**On device:**
1. Tap "Use Google Sign-In" button
2. Watch for:
   - ✅ Google account selection dialog (SUCCESS)
   - ❌ Error 10 again (SHA-1 still not recognized)
   - ❌ Different error (different problem)

---

## 🔧 If Still Getting Error 10

### Check 1: Verify Package Name Consistency
All three must be EXACTLY the same:
1. Google Cloud Console
2. `android/app/build.gradle.kts`: `namespace = "com.example.golf_score_app"`
3. `android/app/google-services.json`: `"package_name": "com.example.golf_score_app"`

### Check 2: Verify SHA-1 Format
The SHA-1 must use COLONS, not lowercase without colons:
- ✅ Correct: `15:E7:03:09:80:64:C5:A2:1F:AB:AF:A4:03:A2:21:F3:65:AA:AC:B0`
- ❌ Wrong: `15e70309806c5a21fab afa403a221f365aaacb0`

### Check 3: Wait Longer
Sometimes Google takes 10-15 minutes (or rarely, up to 1 hour) to propagate changes.

### Check 4: Use Different Google Account
Try signing in with a different Google account - sometimes there are account-specific caching issues.

### Check 5: Check OAuth Consent Screen
1. Go to: https://console.cloud.google.com/apis/consent
2. Verify it's configured (even for testing)
3. Make sure you're not on "Internal" testing app type if this is public

---

## 📝 Summary of Commands

### Get Your Debug SHA-1
```cmd
keytool -list -v -keystore "%USERPROFILE%\.android\debug.keystore" -alias androiddebugkey -storepass android -keypass android | findstr "SHA1"
```

### Get SHA-1 from Gradle
```cmd
cd d:\project\golf\golf-score_app_1\android
gradlew signingReport
```

### Test Build
```cmd
cd d:\project\golf\golf-score_app_1
flutter clean
flutter pub get
flutter run
```

### Nuclear Reset
```cmd
del "%USERPROFILE%\.android\debug.keystore"
keytool -genkey -v -keystore "%USERPROFILE%\.android\debug.keystore" -keyalg RSA -keysize 2048 -validity 10000 -alias androiddebugkey -storepass android -keypass android -dname "CN=Android Debug,O=Android,C=US"
```

---

## 🆘 If You're Still Stuck

Please run these commands and share the output:

1. **Your actual debug SHA-1:**
   ```cmd
   keytool -list -v -keystore "%USERPROFILE%\.android\debug.keystore" -alias androiddebugkey -storepass android -keypass android | findstr "SHA1"
   ```

2. **Gradle signingReport:**
   ```cmd
   cd d:\project\golf\golf-score_app_1\android
   gradlew signingReport
   ```

3. **Flutter Doctor:**
   ```cmd
   flutter doctor -v
   ```

With this information, I can help you identify exactly what's wrong and fix it!
