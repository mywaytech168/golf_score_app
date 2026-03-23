# 🔑 Alternative: Regenerate Debug Keystore & Update Google Cloud

If you're having trouble adding the SHA-1 in Google Cloud Console, try this approach:

## Step 1: Delete the Old Android Client ID in Google Cloud
1. Go to: https://console.cloud.google.com/apis/credentials
2. Find the Android Client ID (446697241300-vqnlo2l37q8i404n1pa8hg29s1c0ffe9...)
3. Click the three-dot menu (⋮) next to it
4. Select **"Delete"**
5. Confirm deletion

## Step 2: Delete Debug Keystore Locally
```cmd
del "%USERPROFILE%\.android\debug.keystore"
```

This will force Android to create a fresh debug keystore with a new SHA-1 fingerprint the next time you run `flutter run`.

## Step 3: Get the NEW Debug SHA-1
```cmd
keytool -list -v -keystore "%USERPROFILE%\.android\debug.keystore" -alias androiddebugkey -storepass android -keypass android | findstr "SHA1"
```

This will output something like:
```
SHA1: XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX
```

Copy this SHA-1 value (with colons).

## Step 4: Create NEW Android Client ID in Google Cloud
1. Go to: https://console.cloud.google.com/apis/credentials
2. Click **"+ CREATE CREDENTIALS"**
3. Select **"OAuth client ID"**
4. Choose **"Android"** as Application type
5. Fill in:
   - **Package name**: `com.example.golf_score_app`
   - **SHA-1 certificate fingerprint**: Paste the SHA-1 you got from Step 3
6. Click **"Create"**

## Step 5: Update google-services.json
The new google-services.json might have a different API key. You'll need to:
1. Download the google-services.json from Google Cloud
2. Replace the file at: `android/app/google-services.json`

## Step 6: Test
```cmd
flutter clean
flutter pub get
flutter run
```

---

## Why This Works

The problem with the existing setup is likely:
1. The SHA-1 in Google Cloud doesn't match your actual debug keystore
2. The UI to add multiple SHA-1s wasn't working properly
3. By deleting and recreating, we force a fresh sync

This approach guarantees that the SHA-1 in Google Cloud matches your actual keystore.

---

## ⚠️ Important Notes

- **Only delete the debug keystore** (debug.keystore). Never delete production keystores!
- After deleting debug.keystore, the next `flutter run` will automatically create a new one
- Your app data on the emulator/device will NOT be affected
- This ONLY affects development builds, not production

---

## If This Still Doesn't Work

The issue might be:
1. Your Google Cloud project is misconfigured
2. You need to enable Google Sign-In API in Google Cloud
3. OAuth consent screen needs configuration

Try:
1. Go to: https://console.cloud.google.com/apis/library
2. Search for: **"Google Sign-In API"**
3. Click on it and ensure it's **ENABLED**

Then go to: https://console.cloud.google.com/apis/consent
And make sure your OAuth consent screen is configured (even if just for testing).
