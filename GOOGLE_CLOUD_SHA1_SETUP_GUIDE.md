# 🔑 Google Cloud Console - Add Debug SHA-1 Fingerprint Guide

## Problem
Google Cloud Console doesn't show an obvious option to add a new SHA-1 fingerprint to Android credentials.

## Solution

### Step 1: Access Google Cloud Console
1. Go to: https://console.cloud.google.com/
2. Select your project: **golf-score-app** (or your project name)
3. Left sidebar → **APIs & Services** → **Credentials**

### Step 2: Find Your Android OAuth Client
- Look for an entry labeled **"Android"** under **OAuth 2.0 Client IDs**
- It should show your Client ID: `446697241300-vqnlo2l37q8i404n1pa8hg29s1c0ffe9`
- **Click on it** to open the detail view

### Step 3: Add SHA-1 Fingerprint (The Key Step!)
Once you open the Android Client ID details, you should see:

```
Certificate fingerprints:
  SHA-1: 05:CE:8D:27:F9:6B:44:6D:56:02:9F:9B:2B:DE:D0:77:BA:98:A5:26
```

**Important: The input field to add more SHA-1s appears BELOW the existing list.**

Look for one of these:
- A button that says **"Add fingerprint"** or **"+"**
- An input field labeled **"SHA-1"** 
- Or an expandable section for **"Certificate fingerprints"**

### Step 4: Enter Debug SHA-1
Paste this debug SHA-1 in the new input field:
```
15:E7:03:09:80:64:C5:A2:1F:AB:AF:A4:03:A2:21:F3:65:AA:AC:B0
```

### Step 5: Save
- Click **"Save"** or **"Update"** button
- Wait 5-10 minutes for changes to propagate

---

## ⚠️ If You Don't See an "Add" Button

### Reason 1: You Haven't Created the Android Credential Yet
If there's NO Android Client ID in your Credentials list:

1. Click **"+ CREATE CREDENTIALS"** → **"OAuth client ID"**
2. Choose **Application type: Android**
3. Fill in:
   - **Package name**: `com.example.golf_score_app`
   - **SHA-1 certificate fingerprints**: 
     ```
     05:CE:8D:27:F9:6B:44:6D:56:02:9F:9B:2B:DE:D0:77:BA:98:A5:26
     ```
4. Click **"Create"**
5. Then edit it again to add the debug SHA-1

### Reason 2: The UI is Different in Your Google Cloud Version
Try this alternative approach:

1. Go to: **APIs & Services** → **Credentials**
2. Look for the Android Client ID and click **"Download JSON"** or the **three-dot menu** (⋮)
3. Select **"Edit"** or **"Edit OAuth client"**
4. You should now see an edit form with the SHA-1 field

---

## 📝 Complete SHA-1 Reference

| Type | SHA-1 |
|------|-------|
| **Production/Release** | `05:CE:8D:27:F9:6B:44:6D:56:02:9F:9B:2B:DE:D0:77:BA:98:A5:26` |
| **Debug** | `15:E7:03:09:80:64:C5:A2:1F:AB:AF:A4:03:A2:21:F3:65:AA:AC:B0` |

**Both should be registered in Google Cloud Console.**

---

## ❓ Troubleshooting

### Q: I see the production SHA-1 but no way to add debug SHA-1
**A:** Look for these UI elements:
- **"Add another SHA-1"** link
- **"+ Add fingerprint"** button  
- **"Edit"** button to modify the certificate section
- Try clicking directly on the SHA-1 field to enable editing

### Q: The page looks different than described
**A:** Google updates their UI periodically. Try:
1. Refresh the page (Ctrl+R)
2. Clear browser cache
3. Try a different browser
4. Try the OAuth 2.0 Client IDs page at: https://myaccount.google.com/apppasswords (alternative view)

### Q: Still can't find it?
**A:** Delete the current Android Client ID and recreate it with BOTH SHA-1s:
1. Click the three-dot menu (⋮) next to the Android Client ID
2. Select **"Delete"**
3. Click **"+ CREATE CREDENTIALS"** → **"OAuth client ID"**
4. Choose **Android**
5. Fill in package name: `com.example.golf_score_app`
6. In **"SHA-1 certificate fingerprints"** field, add both:
   ```
   05:CE:8D:27:F9:6B:44:6D:56:02:9F:9B:2B:DE:D0:77:BA:98:A5:26
   ```
   Then after creation, edit again to add:
   ```
   15:E7:03:09:80:64:C5:A2:1F:AB:AF:A4:03:A2:21:F3:65:AA:AC:B0
   ```

---

## ✅ After Adding SHA-1

Once you've successfully added the debug SHA-1:

1. **Wait 5-10 minutes** for Google's servers to propagate the change

2. **Test on your device:**
   ```cmd
   cd d:\project\golf\golf-score_app_1
   flutter clean
   flutter pub get
   flutter run
   ```

3. **Expected result:**
   - Tap "Use Google Sign-In" button
   - See Google account selection dialog (NOT Error 10)
   - Login should succeed

---

## 🔗 Quick Links

- **Google Cloud Console**: https://console.cloud.google.com/
- **OAuth Consent Screen**: https://console.cloud.google.com/apis/consent
- **Credentials Page**: https://console.cloud.google.com/apis/credentials
- **Android SDK Settings**: https://developer.android.com/studio/command-line/keytool

---

## 📞 Need More Help?

If you still can't find where to add the SHA-1, please:
1. Take a screenshot of the Android Client ID details page
2. Look for a button/link with any of these labels:
   - "Add"
   - "Edit"
   - "Manage"
   - "Add fingerprint"
   - "Add SHA-1"
   - "+"
3. Share what you see, and I can provide more specific guidance
