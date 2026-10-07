# Dhundo (ढूंढो) — Presentation Deck & Project Guide
**Lost & Found Map Assistant**

---

## 📌 Slide 1: Title & Overview
* **App Name**: **Dhundo**
* **Tagline**: Hyperlocal Lost & Found Map Assistant
* **Subtitle**: Connecting communities to recover lost belongings through geospatial intelligence, proximity matching, and privacy-first design.
* **Tech Stack**: Flutter, Dart, Firebase Auth & Cloud Firestore, OpenStreetMap (flutter_map), OSRM Routing, Nominatim API.
* **Design Language**: Obsidian Dark Theme, Custom Glassmorphism, Material 3.

---

## 📌 Slide 2: Societal Problem & Motivation (Rubric 1)
* **The Problem**: Daily loss of critical valuables (wallets, keys, gadgets, IDs, pets) in crowded public areas (campuses, transit hubs, malls).
* **Flaws in Existing Methods**:
  * *WhatsApp & Social Media Groups*: Unstructured, buried by chat noise, no geospatial tagging, exposes personal phone numbers.
  * *Police Desks / Lost Desks*: Fragmented, paper-based, slow, limited to single physical locations.
  * *Scams & Impostors*: Public posts attract fraudsters claiming items that do not belong to them.
* **Dhundo's Solution**:
  * Real-time interactive map with color-coded pins.
  * Automated proximity match engine within 10 km.
  * Anti-fraud ownership verification questions.
  * In-app secure communication without sharing personal contact numbers.
  * Midpoint safe handover spot suggestions (police lobbies, cafes).

---

## 📌 Slide 3: Project Objectives Fulfilled
1. **Interactive Visual Mapping**: OpenStreetMap rendering with category filters and tile caching.
2. **Autonomous Proximity Matching**: Client-side Haversine matching within a 10 km radius.
3. **Privacy & Security**: Built-in messaging and VoIP calling without phone number sharing.
4. **Anti-Scam Claim Protection**: Mandatory ownership verification questions before chat opens.
5. **Safe Physical Exchanges**: Automated midpoint calculation + Nominatim API safe spots + OSRM turn-by-turn routing.
6. **Community Trust**: Rating dialog, Karma points, and Samaritan badges.

---

## 📌 Slide 4: Target Audience & Deployment
* **Target Audience**:
  * College/University students & staff.
  * Daily commuters (Metro, train, bus terminals).
  * Pet owners needing urgent local neighborhood search.
  * Visitors at malls, parks, and events.
* **Deployment Environments**:
  * Urban metro cities, educational campuses, residential societies, corporate tech parks.

---

## 📌 Slide 5: Core Feature Ecosystem
1. **Interactive Map View**: OpenStreetMap with Red (Lost) and Green (Found) pins, category chips, and cached tiles.
2. **Proximity Engine**: 10 km radius match detection matching opposite types (Lost vs. Found).
3. **Neighborhood Amber Alert**: Pulsing banner and glowing markers for urgent lost items/pets.
4. **In-App Messaging & Live Location**: Chat with location pinning and real-time live coordinate sharing.
5. **In-App VoIP Calling**: Firestore signaling with call states (ringing, connected, ended), timer, mute, and speaker.
6. **Turn-by-Turn Navigation & Simulator**: OSRM polyline routing with walking/driving profiles and an animated simulation mode for live demos.

---

## 📌 Slide 6: Safety, Anti-Scam & Trust Flow
* **Verification Question**: Reporter sets a secret question; claimant must answer before initiating chat.
* **Safe Handover Spots**: Nominatim queries nearby police stations and cafes near the midpoint.
* **Safety Guidelines**: Built-in checklist (public areas, daylight, buddy system).
* **Karma & Badges**: Users earn +15 Karma per resolution; unlocks *Good Citizen*, *Super Finder*, and *Trusted Samaritan* badges.

---

## 📌 Slide 7: Technical Architecture
* **Frontend**: Flutter Framework (Dart) with Provider state management.
* **Backend**: Firebase Authentication, Cloud Firestore (offline persistence enabled), Firebase Storage.
* **Geospatial & Mapping**: `flutter_map`, `latlong2`, `geolocator`, OpenStreetMap tiles.
* **External APIs**: OSRM (route calculation) & OSM Nominatim (reverse geocoding and public places).

---

## 📌 Slide 8: Self-Learning & Custom Logic (Rubric 2)
1. **Client-Side Haversine Spatial Matching**: Avoided Firestore geospatial limitations by computing in-memory distance formulas within a 10 km threshold.
2. **Index-Free Query Architecture**: Avoided composite index crashes by using single-field streams combined with in-memory Dart filtering.
3. **GPS Route Simulator**: Created an animated polyline navigator allowing live indoor demonstrations without stepping outside.
4. **Tile Disk Caching (`CachedTileProvider`)**: Implemented local disk caching for OpenStreetMap tiles using `cached_network_image`.
5. **Firestore VoIP Signaling**: Built real-time call states without paid third-party telephony services.

---

## 📌 Slide 9: Standardized & Workable App (Rubric 3)
* **Production-Ready UI**: Unified theme system (`AppTheme`), glassmorphic cards, responsive layouts.
* **Offline Resilience**: Offline Firestore caching enabled for viewing items without an active connection.
* **Graceful Degradation**: Fallback coordinates and default safe spots if location or network calls timeout.
* **App Lifecycle**: Case resolution flow archives items immediately and removes pins from the active map.

---

## 📌 Slide 10: Hardware & Software Requirements
* **Client Devices**:
  * OS: Android 6.0+ / iOS 12.0+ / Modern Web Browser.
  * Hardware: Dual-Core CPU, 2 GB RAM (4 GB recommended), GPS module, Camera, Internet connection.
* **Development Environment**:
  * Flutter SDK 3.12+, Dart 3.x, Android Studio / VS Code, Java JDK 17, Firebase CLI.

---

## 📌 Slide 11: Work Distribution & Team Contribution (Rubric 4)
* **Role 1 (Backend & Cloud Architecture)**: Firebase Auth, Firestore schema, offline persistence, composite keys.
* **Role 2 (Geospatial & Navigation)**: OpenStreetMap integration, OSRM routing engine, GPS simulation mode.
* **Role 3 (Real-Time Communication & Safety)**: Chat system, VoIP signaling, Safe Places API, verification questions.
* **Role 4 (UI/UX & Quality Assurance)**: Obsidian dark design, glassmorphic widgets, form validations, bug fixing.
* **Team Problem Solving**: Tackled Firestore index limits, built navigation simulator for indoor demos, created anti-scam verification checks.

---

## 📌 Slide 12: Future Scope
* AI image similarity matching (comparing photos of lost and found items).
* Bluetooth BLE beacon / AirTag integration for indoor tracking.
* Push notifications via Firebase Cloud Messaging (FCM).
