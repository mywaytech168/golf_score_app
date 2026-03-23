# 🚀 Quick Action Plan - Get Your Debug SHA-1 NOW

## Step 1: Get Your ACTUAL Debug SHA-1 (2 minutes)

Run this command in your terminal:

```cmd
keytool -list -v -keystore "%USERPROFILE%\.android\debug.keystore" -alias androiddebugkey -storepass android -keypass android | findstr "SHA1"
```

**Expected output:**
```
SHA1: 15:E7:03:09:80:64:C5:A2:1F:AB:AF:A4:03:A2:21:F3:65:AA:AC:B0
```

Or possibly different SHA-1 if you have a different keystore.

⚠️ **The SHA-1 I calculated might not be your ACTUAL one!**

---

## Step 2: Add THAT SHA-1 to Google Cloud (2 minutes)

1. Go to: https://console.cloud.google.com/apis/credentials
2. Find your Android Client ID
3. Click on it
4. Look for "+ Add SHA-1" button
5. Paste the SHA-1 from Step 1 (whatever it shows)
6. Click "Save"

**⚠️ Important**: Use the SHA-1 from YOUR keytool output, not the one I guessed!

---

## Step 3: Wait (5-10 minutes)

Google needs time to sync the change across their servers.

---

## Step 4: Test (2 minutes)

```cmd
cd d:\project\golf\golf-score_app_1
flutter clean
flutter run
```

Then tap "Use Google Sign-In" button on your device.

**Expected:**
- ✅ Google account selection dialog appears
- ✅ You can select account and sign in

**If still Error 10:**
- The SHA-1 might be different
- Or you added it wrong
- Or it hasn't propagated yet

---

## 🎯 TL;DR

1. **Copy the keytool command above**
2. **Run it and get YOUR actual SHA-1** 
3. **Add that SHA-1 to Google Cloud** (not the one I calculated)
4. **Wait 5-10 minutes**
5. **Test**

That's it! The problem is likely that the SHA-1 I calculated doesn't match your actual one.
