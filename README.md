# Dhundo 🔍
### Lost & Found Map Assistant

[![Deploy to GitHub Pages](https://github.com/Saumya-sura/dhundo/actions/workflows/deploy.yml/badge.svg)](https://github.com/Saumya-sura/dhundo/actions/workflows/deploy.yml)
[![Live Demo](https://img.shields.io/badge/Live%20Demo-GitHub%20Pages-brightgreen?style=flat-square&logo=github)](https://saumya-sura.github.io/dhundo/)

🌐 **Live Web App**: [https://saumya-sura.github.io/dhundo/](https://saumya-sura.github.io/dhundo/)

Dhundo is a modern, state-of-the-art Flutter application built to help communities connect and return lost items. Featuring a premium **Obsidian Dark Theme**, real-time map exploration via Google Maps, automated proximity matching, interactive Google Street View 360° panoramas, and direct in-app messaging, Dhundo makes locating lost belongings seamless and collaborative.

---

## 🚀 Key Features

*   **🗺️ Interactive Google Maps Discovery**: Native Google Maps rendering with custom Obsidian Dark styling, category filters, and pin visualizers (🔴 Red for Lost items, 🟢 Green for Found items, 🟠 Amber alerts).
*   **📷 Google Street View 360° Explorer**: Preview actual street-level panoramas for any pinned item or meetup spot with 360° rotation, pitch controls, and zoom.
*   **🤖 Automated Proximity Matching**: Upon submitting a report, Dhundo's matching engine automatically analyzes existing reports in the same category within a **10 km radius** to look for overlaps.
*   **💬 Real-Time Messaging & Live Location**: Coordinate safe handovers with live location sharing, static map previews, and simulated VoIP calling.
*   **⚡ Case Resolution System**: Mark items as resolved/returned inside the chat window, which automatically archives the item and removes its pin from the map.
*   **✨ Premium Glassmorphism & UI**: Built using custom translucent widgets (`GlassCard`), indigo-to-cyan gradients, custom input validations, and smooth micro-animations.

---

## 🛠️ Tech Stack & Dependencies

- **Framework**: [Flutter](https://flutter.dev/) (Dart)
- **State Management**: [Provider](https://pub.dev/packages/provider)
- **Database & Auth**: [Firebase Auth & Cloud Firestore](https://firebase.google.com/)
- **Storage**: [Firebase Storage](https://firebase.google.com/) (for uploading item images)
- **Mapping & Geocoding**: [Google Maps Flutter](https://pub.dev/packages/google_maps_flutter), Google Street View API, Google Geocoding API & [Geolocator](https://pub.dev/packages/geolocator)
- **Design Elements**: [Google Fonts (Outfit/Inter)](https://fonts.google.com/), Custom Glassmorphic Cards, custom route transitions.

---

## ⚙️ Firebase Setup & Configuration

Dhundo is preconfigured to use Firebase. To connect it to your own live Firebase backend, follow these steps:

### Step 1: Install Firebase CLI
1. Ensure you have **Node.js** installed on your system.
2. Install the Firebase CLI globally:
   ```bash
   npm install -g firebase-tools
   ```
3. Authenticate with your Firebase/Google account:
   ```bash
   firebase login
   ```

### Step 2: Activate FlutterFire CLI
Activate the FlutterFire helper tool from your terminal:
```bash
dart pub global activate flutterfire_cli
```

### Step 3: Run FlutterFire Configure
From the root directory of this project (`dhundo`), run:
```bash
flutterfire configure
```
- Select your Firebase Project (or create a new one).
- Choose the platforms you want to support (Android, iOS, Web).
- This command automatically generates/overwrites `lib/firebase_options.dart` and configures platform files (`google-services.json` and `GoogleService-Info.plist`).

### Step 4: Enable Core Services in Console
Go to the [Firebase Console](https://console.firebase.google.com/) and enable:
1. **Authentication**: Enable `Email/Password` login.
2. **Cloud Firestore**: Enable Firestore Database (preferably in Test Mode for development).
3. **Firebase Storage**: Enable Storage to allow user image uploads.

---

## 📂 Project Architecture

```
lib/
├── main.dart                 # App initialization, Firebase setup, and Auth redirection
├── models/
│   ├── item_model.dart       # Representation of a Lost/Found report
│   └── chat_model.dart       # Representation of ChatRooms and Messages
├── services/
│   └── firebase_service.dart # Realtime Firestore syncing, Authentication, and proximity queries
├── theme/
│   └── app_theme.dart        # Unified brand color schemes, gradients, and custom themes
├── widgets/
│   ├── glass_card.dart       # Custom glassmorphic panel overlay
│   ├── custom_textfield.dart # Reusable validation text inputs
│   └── custom_button.dart    # Premium gradient buttons with loading indicators
└── pages/
    ├── auth_page.dart        # Slide-based sliding Auth portal (Login / Register)
    ├── home_page.dart        # Main hub holding the bottom navigation bar
    ├── map_view.dart         # OpenStreetMap pin visualizer & details sheet
    ├── feed_view.dart        # Searchable and categorized list of reports
    ├── report_page.dart      # Submission wizard with draggable pin map-picker
    ├── chat_page.dart        # Real-time message exchange and resolution triggers
    ├── chats_list_page.dart  # Inbox list of all active chats
    └── potential_matches_page.dart # Matches comparison screen
```

---

## 🛠️ Sprint 1 Fixes Applied

The following issues were successfully addressed during Sprint 1:
- **Index-Free Queries**: Re-engineered Firestore streams in `getUserChatRooms()` and `checkPotentialMatches()` to avoid requiring complex composite indexes. Filtering and sorting (like distance calculations and message times) are now evaluated client-side, making the app run out-of-the-box on new Firebase databases.
- **Found Form Success Text**: Resolved a state bug where submitting a found item would display a snackbar declaring a "Lost report posted successfully!".
- **BuildContext Integrity**: Cleared async-gap build context lint warnings across dialog handlers.