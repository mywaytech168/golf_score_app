# 🎯 Visual Guide: Where to Click in Google Cloud Console

## Current Situation
You said: "Google 上面沒有新增的設定" (There's no option to add new settings in Google Cloud)

This could mean:
1. You can't find where to add the SHA-1
2. There's no visible button to add more fingerprints
3. The UI looks different than expected

## Solution: Where to Look

### Step 1: Go to Credentials Page
```
https://console.cloud.google.com/apis/credentials
```

You should see a list of credentials.

### Step 2: Find the Android Client ID
Look for something labeled:
- "OAuth 2.0 Client ID" AND
- "Application type: Android"
OR
- "Android Client ID"

It will show your package name: `com.example.golf_score_app`

### Step 3: CLICK on the Credential Entry Itself

**IMPORTANT**: You need to CLICK directly on the credential entry (not just view it in the list).

When you click on it, a **detail page** will open showing:
```
═════════════════════════════════════════════════════════════
  OAuth 2.0 Client ID

  Client ID: 446697241300-vqnlo2l37q8i404n1pa8hg29s1c0ffe9.apps.googleusercontent.com

  ┌─────────────────────────────────────────────────────────┐
  │                                                         │
  │  Package name: com.example.golf_score_app              │
  │                                                         │
  │  SHA-1 certificate fingerprints:                        │
  │  • 05:CE:8D:27:F9:6B:44:6D:56:02:9F:9B:2B:DE:D0:77:BA │
  │    :98:A5:26                                            │
  │                                                         │
  │  [+ Add SHA-1]  or  [Edit]  button  ← CLICK HERE        │
  │                                                         │
  └─────────────────────────────────────────────────────────┘

═════════════════════════════════════════════════════════════
```

### Step 4: Click "Add SHA-1" or "Edit"

**Option A: If you see "+ Add SHA-1" button**
1. Click it
2. A new input field appears
3. Paste the debug SHA-1:
   ```
   15:E7:03:09:80:64:C5:A2:1F:AB:AF:A4:03:A2:21:F3:65:AA:AC:B0
   ```
4. Click "Save" or "Update"

**Option B: If you see "Edit" button**
1. Click "Edit"
2. You'll see a form to edit the credentials
3. Find the "SHA-1 certificate fingerprints" section
4. Add the debug SHA-1 to the list
5. Click "Save" or "Update"

**Option C: If neither button appears**
1. Try clicking directly on the SHA-1 value itself (to edit inline)
2. Look for a pencil/edit icon next to the certificate section
3. Look in a sidebar or expandable menu

---

## 🔍 What to Look For

### These buttons/options SHOULD appear somewhere:
- [ ] "Edit" button (top right or bottom of the detail view)
- [ ] "+ Add SHA-1" button
- [ ] "+ Add fingerprint" button
- [ ] "Add another certificate" link
- [ ] Input field with "SHA-1" label
- [ ] A pencil/edit icon next to the certificate section

### If you see NONE of these:
The credential might be locked or in view-only mode. Try:
1. Right-click on the credential entry → "Edit"
2. Look for a three-dot menu (⋮) → "Edit"
3. Click the credential name/ID itself to enter edit mode

---

## 📸 Common UI Variations

### Google Cloud UI Variation 1:
```
[Delete] [Create similar] [...]

Android Client ID
├─ Client ID: 446697241300-...
├─ Package name: com.example.golf_score_app
└─ Certificate fingerprints:
   └─ SHA-1: 05:CE:8D:27:F9:6B:...
   └─ [+ Add]  ← CLICK HERE
```

### Google Cloud UI Variation 2:
```
Android

OAuth 2.0 Client ID
446697241300-vqnlo2l37q8i404n1pa8hg29s1c0ffe9.apps.googleusercontent.com
com.example.golf_score_app

[Edit]  [Delete]  [...]  ← CLICK [Edit]

(Click Edit to see the Add SHA-1 option)
```

### Google Cloud UI Variation 3:
```
OAuth Client ID

Package name
com.example.golf_score_app

Fingerprint (SHA-1)
05:CE:8D:27:F9:6B:44:6D:56:02:9F:9B:2B:DE:D0:77:BA:98:A5:26
[+ Add more fingerprints]  ← CLICK HERE
```

---

## 🚨 If STILL Can't Find It

### Nuclear Option: Delete and Recreate
1. Find the Android Client ID
2. Click the three-dot menu (⋮) 
3. Select **"Delete"**
4. Click **"+ CREATE CREDENTIALS"**
5. Select **"OAuth client ID"**
6. Choose **"Android"**
7. Fill in:
   - Package name: `com.example.golf_score_app`
   - SHA-1: `15:E7:03:09:80:64:C5:A2:1F:AB:AF:A4:03:A2:21:F3:65:AA:AC:B0` (debug)
8. Create it
9. Then edit again to add the production SHA-1:
   - `05:CE:8D:27:F9:6B:44:6D:56:02:9F:9B:2B:DE:D0:77:BA:98:A5:26`

---

## 📋 Checklist

Before you start:
- [ ] I'm logged into Google Cloud Console with the correct account
- [ ] I selected the correct project (golf-score-app or similar)
- [ ] I'm on the Credentials page (APIs & Services → Credentials)
- [ ] I can see the Android Client ID in the list

When adding SHA-1:
- [ ] I found the Android Client ID entry
- [ ] I clicked on it to open the detail view
- [ ] I found the "Add SHA-1" or "Edit" button
- [ ] I entered the debug SHA-1: `15:E7:03:09:80:64:C5:A2:1F:AB:AF:A4:03:A2:21:F3:65:AA:AC:B0`
- [ ] I clicked "Save" or "Update"
- [ ] The page refreshed and shows both SHA-1s

After adding:
- [ ] I waited 5-10 minutes
- [ ] I ran `flutter clean` and `flutter run`
- [ ] I tested Google Sign-In on my device
- [ ] I see the account selection dialog (NOT Error 10)

---

## 💬 Still Stuck?

If you still can't find where to add the SHA-1, please tell me:
1. What exactly is shown on your Android Client ID detail page?
2. Do you see the existing production SHA-1 listed?
3. What buttons/options do you see below or next to the SHA-1?
4. Are there any "Edit", "Add", "Manage" buttons anywhere on the page?

Screenshot would be helpful if possible!
