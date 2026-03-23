# 🔐 Google Cloud Console - Add Debug SHA-1 (Visual Step-by-Step)

## Status: ✅ `google-services.json` Updated
The local `google-services.json` has been updated with both SHA-1s:
- Production: `05ce8d27f96b446d56029f9b2bded077ba98a526`
- Debug: `15e70309806c5a21fab afa403a221f365aaacb0`

**⚠️ But you MUST also add it in Google Cloud Console for it to work!**

---

## 📋 What You Need to Do in Google Cloud Console

### Go to Google Cloud Console
1. Open: **https://console.cloud.google.com/**
2. Make sure you're logged in with the same Google account you used to create the OAuth credentials
3. Select your project: **golf-score-app** (or whatever you named it)

### Navigate to Credentials
1. Left sidebar → Click **APIs & Services**
2. Click **Credentials**
3. You should see a list of credentials

### Find the Android Client ID
Look for an entry with:
- **Type**: OAuth 2.0 Client ID
- **Application type**: Android
- **Name**: Usually shows the package name or "Android"

You should see something like:
```
Client ID: 446697241300-vqnlo2l37q8i404n1pa8hg29s1c0ffe9.apps.googleusercontent.com
Package name: com.example.golf_score_app
SHA-1: 05:CE:8D:27:F9:6B:44:6D:56:02:9F:9B:2B:DE:D0:77:BA:98:A5:26
```

### Click on It to Edit
**Click directly on the credential entry** to open its details page.

You should see something like:

```
──────────────────────────────────────────
  OAuth 2.0 Client ID (Android)
  
  Client ID: 446697241300-vqnlo2l37q8i404n1pa8hg29s1c0ffe9...
  
  Package name: com.example.golf_score_app
  
  SHA-1 certificate fingerprints:
  ┌─────────────────────────────────────────────────┐
  │ 05:CE:8D:27:F9:6B:44:6D:56:02:9F:9B:2B:DE:D0   │
  │ :77:BA:98:A5:26                                 │
  └─────────────────────────────────────────────────┘
  
  [+ Add SHA-1]  or  [Edit]  button
  
──────────────────────────────────────────
```

### Look for These UI Elements to Add a New SHA-1:
- **Option A**: A button that says **"+ Add SHA-1"** or **"Add fingerprint"**
- **Option B**: An input field with a **"+"** button next to the SHA-1 list
- **Option C**: Click an **"Edit"** button to modify the certificate section
- **Option D**: Click directly in the SHA-1 field to enable editing

### Enter the Debug SHA-1
Once you find where to add it, enter:
```
15:E7:03:09:80:64:C5:A2:1F:AB:AF:A4:03:A2:21:F3:65:AA:AC:B0
```

(Note: Use colons `:` between pairs, not dashes like in the lowercase version)

### Click Save or Update
Look for a button that says:
- **"Save"**
- **"Update"**
- **"Create"**
- **"Done"**

Click it to save your changes.

---

## ⏰ Wait for Propagation
After saving, **wait 5-10 minutes** for Google's servers to update.

---

## 🧪 Test It
Once the propagation is complete:

```cmd
cd d:\project\golf\golf-score_app_1
flutter clean
flutter pub get
flutter run
```

Then on your device:
1. Tap **"Use Google Sign-In"** button
2. **Expected**: See Google account selection dialog
3. **NOT Expected**: Error 10 (which means SHA-1 still not recognized)

---

## ❌ If You Still Get Error 10

### Check 1: Verify Both SHA-1s Are in Google Cloud
Go back to the Android Client ID credentials and confirm you see BOTH:
- `05:CE:8D:27:F9:6B:44:6D:56:02:9F:9B:2B:DE:D0:77:BA:98:A5:26` (production)
- `15:E7:03:09:80:64:C5:A2:1F:AB:AF:A4:03:A2:21:F3:65:AA:AC:B0` (debug)

### Check 2: Verify Package Name is Correct
The package name in Google Cloud should be:
```
com.example.golf_score_app
```

Check that it exactly matches in:
- Google Cloud Console
- `android/app/build.gradle.kts`: `namespace = "com.example.golf_score_app"`
- `android/app/google-services.json`: `"package_name": "com.example.golf_score_app"`

### Check 3: Clear Everything and Try Again
```cmd
flutter clean
rm -r build/
flutter pub get
flutter run
```

### Check 4: Verify You're Using the Correct Debug Keystore
Run this command to get your ACTUAL debug keystore SHA-1:
```cmd
keytool -list -v -keystore "%USERPROFILE%\.android\debug.keystore" -alias androiddebugkey -storepass android -keypass android | findstr "SHA1"
```

The output should show:
```
SHA1: 15:E7:03:09:80:64:C5:A2:1F:AB:AF:A4:03:A2:21:F3:65:AA:AC:B0
```

If it shows something different, you'll need to update Google Cloud with the correct SHA-1.

---

## 📞 Still Having Issues?

Please provide:
1. Screenshot of the Android Client ID page from Google Cloud Console
2. Output of the keytool command above
3. The error message you see on your device when trying to sign in

And I'll help you troubleshoot further!
