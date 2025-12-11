# Google Maps Platform Setup Guide

**Purpose**: This guide outlines the steps to create a Google Cloud account, enable the necessary APIs for a ride-hailing application (like Uber/Lyft), and generate the required API keys.

---

## **Step 1: Create a Google Cloud Account**
1.  Go to the [Google Cloud Console](https://console.cloud.google.com/).
2.  Sign in with your Google (Gmail) account.
3.  If this is your first time, you may need to accept the Terms of Service.

## **Step 2: Create a New Project**
1.  In the top navigation bar, click the **Project Dropdown** (it might say "Select a project" or show an existing project name).
2.  Click **New Project** in the top right of the popup.
3.  **Project Name**: Enter a name like `Skyline-App-Prod`.
4.  **Organization**: Leave as "No organization" unless you have a corporate account.
5.  Click **Create**.
6.  *Wait a moment for the project to be created, then ensure you select it from the notification or project dropdown.*

## **Step 3: Enable Billing (Critical)**
Google Maps Platform is a paid service (with a $200 free monthly tier), but it **requires** a billing account to work.
1.  Go to the **Billing** section in the left menu.
2.  Click **Link a billing account** or **Manage billing accounts**.
3.  Click **Create Account** and follow the prompts to add a credit card.
    *   *Note: You won't be charged unless you exceed the free tier usage, but proper APIs won't return data without this.*

## **Step 4: Enable Required APIs**
You need to enable a suite of APIs for the app to function correctly.
Go to **APIs & Services > Library** from the left menu.
Search for and **ENABLE** each of the following APIs one by one:

### **1. Maps SDK for Mobile (Rendering the Map)**
*   **Android**: [Maps SDK for Android](https://console.cloud.google.com/marketplace/product/google/maps-android-backend.googleapis.com)
*   **iOS**: [Maps SDK for iOS](https://console.cloud.google.com/marketplace/product/google/maps-ios-backend.googleapis.com)
    *   *Why needed*: Renders the actual map tiles on the phone.

### **2. Places API (Search & Autocomplete)**
*   **Link**: [Places API (New)](https://console.cloud.google.com/marketplace/product/google/places-backend.googleapis.com)
    *   *Why needed*: Powers the "search bar" autocomplete (e.g., typing "Heathrow" suggests "Heathrow Airport").

### **3. Directions API (Routing)**
*   **Link**: [Directions API](https://console.cloud.google.com/marketplace/product/google/directions-backend.googleapis.com)
    *   *Why needed*: Draws the blue route line on the map from Pickup to Dropoff.

### **4. Geocoding API (Address Conversion)**
*   **Link**: [Geocoding API](https://console.cloud.google.com/marketplace/product/google/geocoding-backend.googleapis.com)
    *   *Why needed*: Converts GPS coordinates (Lat/Lng) into readable addresses ("123 Main St") and vice versa.

### **5. Distance Matrix API (ETA & Pricing)**
*   **Link**: [Distance Matrix API](https://console.cloud.google.com/marketplace/product/google/distance-matrix-backend.googleapis.com)
    *   *Why needed*: Calculates travel time (ETA) and distance for fare calculation.

---

## **Step 5: Generate API Keys**
Once all APIs are enabled:
1.  Go to **APIs & Services > Credentials**.
2.  Click **+ CREATE CREDENTIALS** at the top.
3.  Select **API Key**.
4.  Copy the generated key (Starts with `AIza...`).

### **Step 6: Security Best Practices (Recommended)**
To prevent unauthorized usage of your credit card, you should create **two** separate keys:

**Key 1: Mobile App Key (Restricted)**
*   Click the **Pencil icon** to edit the key you just made.
*   **Name**: `Skyline Mobile App Key`
*   **Application restrictions**: Select **Android apps**.
    *   Click **ADD AN ITEM**.
    *   **Package name**: Enter `com.mktours.app` (or the specific package name provided by your developer).
    *   **SHA-1 certificate fingerprint**: Enter the fingerprint provided by your developer.
    *   Click **DONE**.
*   **Application restrictions** (Switch to iOS): Select **iOS apps** (You may need to create a separate key if you can't select both, but usually you can add multiple items). *Better Practice: Create a separate key for iOS*.
    *   Let's stick to one key for simplicity if possible, or create two: `Skyline Android Key` and `Skyline iOS Key`.
    *   For **iOS apps**: Click **ADD AN ITEM**.
    *   **Bundle ID**: Enter `com.mktours.app`.
    *   Click **DONE**.
*   **API restrictions**: Select **Restrict key**.
    *   Click the dropdown and select *only*: "Maps SDK for Android", "Maps SDK for iOS", and "Places API" (New).
    *   Click **OK** then **SAVE**.

**Key 2: Backend Server Key (Secret)**
*   Create a *new* second key.
*   **Name**: `Skyline Backend Key`
*   **Application restrictions**: Select **IP addresses (web servers, cron jobs, etc.)**.
    *   Click **ADD AN ITEM**.
    *   Enter your server's public IP address.
    *   Click **DONE**.
*   **API restrictions**: Select **Restrict key**.
    *   Select *only*: "Directions API", "Geocoding API", and "Distance Matrix API".
    *   Click **OK** then **SAVE**.

---

## **Summary Checklist for Developer**
Please provide the following to the development team:
- [ ] **Google Maps API Key** (starts with `AIza...`)
- [ ] Confirmation that **Billing** is enabled.
- [ ] Confirmation that all **5 APIs** listed above are enabled.
