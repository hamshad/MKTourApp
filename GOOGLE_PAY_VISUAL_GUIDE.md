# 🎨 Visual Guide - Google Pay Implementation

## Flow Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                    PAYMENT SELECTION MODAL                          │
│                                                                     │
│  💰 Select Payment Method                                          │
│  ─────────────────────────────────────                             │
│                                                                     │
│  ┌─────────────────────────────────────┐                          │
│  │  💵 Cash                            │                          │
│  │  Pay directly to driver             │ ← Available on ALL       │
│  │  [tap]                              │   platforms              │
│  └─────────────────────────────────────┘                          │
│                                                                     │
│  ┌──────────────── PLATFORM SPECIFIC ─────────────────┐           │
│  │                                                     │           │
│  │  IF ANDROID (🤖):                                  │           │
│  │  ┌─────────────────────────────────────┐          │           │
│  │  │  💳 Pay Online                      │          │           │
│  │  │  Pay with Google Pay or Card       │          │           │
│  │  │  [tap → sends 'pay_online']        │          │           │
│  │  └─────────────────────────────────────┘          │           │
│  │                                                     │           │
│  │  IF iOS (🍎):                                      │           │
│  │  ┌─────────────────────────────────────┐          │           │
│  │  │  🔗 Payment Link                    │          │           │
│  │  │  Pay via online link                │          │           │
│  │  │  [tap → sends 'payment_link']       │          │           │
│  │  └─────────────────────────────────────┘          │           │
│  │                                                     │           │
│  └─────────────────────────────────────────────────────┘           │
└─────────────────────────────────────────────────────────────────────┘
```

## Android: Pay Online Flow

```
┌────────────────────────────────────────────────────────────────┐
│                  USER SELECTS "PAY ONLINE"                    │
│                                                               │
│  App sends:                                                  │
│  POST /select-payment-method                                 │
│  { "paymentMethod": "pay_online" }                          │
└────────────────────────────────────────────────────────────────┘
                              ↓
┌────────────────────────────────────────────────────────────────┐
│                    BACKEND RECEIVES                            │
│                                                               │
│  1. Validate ride and user                                  │
│  2. Create Stripe PaymentIntent with:                      │
│     - amount: £25.00 = 2500 pence                         │
│     - currency: 'gbp'                                      │
│     - payment_method_types: ['card', 'google_pay']  ⚠️   │
│     - metadata: { rideId, userId }                        │
│  3. Return response:                                        │
│  {                                                          │
│    "success": true,                                         │
│    "data": {                                                │
│      "ride": {                                              │
│        "paymentMethod": "stripe",     ← IMPORTANT!         │
│        "clientSecret": "pi_..._secret_...",               │
│        "amount": 2500,                                      │
│        "currency": "GBP"                                    │
│      }                                                       │
│    }                                                         │
│  }                                                           │
└────────────────────────────────────────────────────────────────┘
                              ↓
┌────────────────────────────────────────────────────────────────┐
│                   FLUTTER APP RECEIVES                         │
│                                                               │
│  Checks: paymentMethod == 'stripe' ✅                       │
│  Extracts: clientSecret                                     │
│  Calls: StripeService.processPayment(clientSecret)        │
└────────────────────────────────────────────────────────────────┘
                              ↓
┌────────────────────────────────────────────────────────────────┐
│            STRIPE SERVICE INITIALIZES PAYMENT SHEET            │
│                                                               │
│  1. Detects: Platform.isAndroid → TRUE                      │
│  2. Configures:                                              │
│     - paymentMethodOrder: ['google_pay', 'card']           │
│     - Google Pay with merchant country: GB                │
│     - Style: Light theme                                   │
│  3. Logs:                                                    │
│     ✅ Platform: ANDROID                                   │
│     ✅ Platform Pay Supported: true                        │
│     ✅ 🤖 ANDROID DETECTED - Configuring Google Pay       │
│     ✅ Google Pay payment sheet initialized                │
│  4. Presents payment sheet to user                         │
└────────────────────────────────────────────────────────────────┘
                              ↓
┌────────────────────────────────────────────────────────────────┐
│              STRIPE PAYMENT SHEET OPENS TO USER                │
│                                                               │
│  ╔═════════════════════════════════════════════════════════╗ │
│  ║  💳 Select Payment Method                               ║ │
│  ╠═════════════════════════════════════════════════════════╣ │
│  ║  🟢 Google Pay   ← PRIMARY OPTION                       ║ │
│  ║  [User taps to pay with Google Pay]                    ║ │
│  ║                                                         ║ │
│  ║  Or pay with a card                                   ║ │
│  ║  ─────────────────────────────────────────────        ║ │
│  ║  💳 Card Number: [4242 4242 4242 4242]               ║ │
│  ║  MM/YY: [12/25]  CVC: [123]                          ║ │
│  ║                                                         ║ │
│  ║  [Pay £25.00] 🔒                                      ║ │
│  ╚═════════════════════════════════════════════════════════╝ │
│                                                               │
│  User selects payment method and completes payment          │
└────────────────────────────────────────────────────────────────┘
                              ↓
┌────────────────────────────────────────────────────────────────┐
│                    PAYMENT SUCCESSFUL                          │
│                                                               │
│  App shows:                                                  │
│  ✅ "Payment Successful! Share OTP with driver."           │
│                                                               │
│  UI updates:                                                 │
│  Payment: Paid Online ✓                                     │
│                                                               │
│  Backend webhook received:                                  │
│  charge.succeeded with PaymentIntent ID                   │
└────────────────────────────────────────────────────────────────┘
```

## iOS: Payment Link Flow

```
┌────────────────────────────────────────────────────────────────┐
│              USER SELECTS "PAYMENT LINK" (iOS ONLY)            │
│                                                               │
│  App sends:                                                  │
│  POST /select-payment-method                                 │
│  { "paymentMethod": "payment_link" }                        │
└────────────────────────────────────────────────────────────────┘
                              ↓
┌────────────────────────────────────────────────────────────────┐
│                    BACKEND RECEIVES                            │
│                                                               │
│  1. Create Stripe Payment Link                             │
│  2. Return:                                                  │
│  {                                                           │
│    "success": true,                                          │
│    "data": {                                                 │
│      "ride": {                                               │
│        "paymentMethod": "payment_link",                     │
│        "paymentUrl": "https://pay.stripe.com/pay/..."     │
│      }                                                        │
│    }                                                          │
│  }                                                            │
└────────────────────────────────────────────────────────────────┘
                              ↓
┌────────────────────────────────────────────────────────────────┐
│              FLUTTER OPENS WEBVIEW                             │
│                                                               │
│  Shows: Payment Link in WebView                             │
│  User completes payment in browser                         │
│  App detects success redirect and closes WebView           │
└────────────────────────────────────────────────────────────────┘
```

## Cash Payment (All Platforms)

```
┌────────────────────────────────────────────────────────────────┐
│                    USER SELECTS "CASH"                        │
│                                                               │
│  App sends:                                                  │
│  POST /select-payment-method                                 │
│  { "paymentMethod": "cash" }                                │
│                                                               │
│  No Stripe involved                                          │
│  Driver will collect payment in person                      │
│                                                               │
│  UI shows:                                                   │
│  Payment: Cash ✓                                            │
└────────────────────────────────────────────────────────────────┘
```

## Key Code Locations

### 1. Payment Selection Modal
**File:** `lib/features/ride/ride_assigned_screen.dart` (Line 2270)

```dart
if (Platform.isAndroid)
  _buildPaymentOption(
    icon: Icons.credit_card,
    title: 'Pay Online',
    subtitle: 'Pay with Google Pay or Card',
    onTap: () => _handlePaymentSelection('pay_online'),  // ← Sends 'pay_online'
  ),
```

### 2. Stripe Configuration for Android
**File:** `lib/core/services/stripe_service.dart` (Line 60)

```dart
if (isAndroid) {
  await Stripe.instance.initPaymentSheet(
    paymentSheetParameters: SetupPaymentSheetParameters(
      paymentIntentClientSecret: clientSecret,
      paymentMethodOrder: const ['google_pay', 'card'],  // ← Google Pay first!
      googlePay: const PaymentSheetGooglePay(
        merchantCountryCode: 'GB',
        testEnv: false,
        currencyCode: 'GBP',
      ),
    ),
  );
}
```

### 3. Backend PaymentIntent (Example: Node.js)
**Required in your backend:**

```javascript
// This MUST be done when paymentMethod === 'pay_online'
const paymentIntent = await stripe.paymentIntents.create({
  amount: Math.round(ride.fare * 100),
  currency: 'gbp',
  payment_method_types: ['card', 'google_pay'],  // ⚠️ CRITICAL!
});
```

---

## Testing Checklist

```
┌─────────────────────────────────────────────────────────┐
│  ✅ FRONTEND (Flutter)                                  │
├─────────────────────────────────────────────────────────┤
│  ✓ Android shows "Pay Online" button                   │
│  ✓ iOS shows "Payment Link" button                     │
│  ✓ Both show "Cash" button                             │
│  ✓ Correct method sent to backend                      │
│  ✓ Stripe logs show proper configuration               │
│  ✓ Google Pay sheet opens with Google Pay visible      │
│  ✓ Payment succeeds and shows success message          │
│  ✓ UI updates with correct payment method label        │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│  ⚠️  BACKEND (Must Verify)                              │
├─────────────────────────────────────────────────────────┤
│  ⚠️  PaymentIntent has payment_method_types           │
│  ⚠️  PaymentIntent includes 'card' AND 'google_pay'   │
│  ⚠️  Response returns paymentMethod: 'stripe'          │
│  ⚠️  Response includes clientSecret                    │
│  ⚠️  Amount is in pence (2500 = £25.00)               │
│  ⚠️  Currency is lowercase 'gbp'                       │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│  🔐 STRIPE DASHBOARD                                    │
├─────────────────────────────────────────────────────────┤
│  🔐 Google Pay is ENABLED                              │
│  🔐 Merchant account is verified                       │
│  🔐 Settings → Payment methods shows Google Pay active │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│  📱 ANDROID DEVICE                                      │
├─────────────────────────────────────────────────────────┤
│  📱 Has Google Play Services (updated)                 │
│  📱 Has Google Pay app installed                       │
│  📱 Has payment method in Google Pay                   │
│  📱 Running latest flutter_stripe version              │
└─────────────────────────────────────────────────────────┘
```

---

## Troubleshooting Tree

```
❌ Google Pay not showing?
├─ Check 1: Backend returning correct response?
│  ├─ Response has paymentMethod: 'stripe'? → YES ✓ Continue
│  └─ Response missing? → Update backend code
│
├─ Check 2: PaymentIntent has correct payment_method_types?
│  ├─ Includes ['card', 'google_pay']? → YES ✓ Continue
│  └─ Missing google_pay? → Update backend PaymentIntent creation
│
├─ Check 3: Stripe Dashboard Google Pay enabled?
│  ├─ Dashboard shows Google Pay as Active? → YES ✓ Continue
│  └─ Disabled? → Enable in Settings → Payment methods
│
├─ Check 4: Device has Google Pay set up?
│  ├─ Google Pay app installed? → YES ✓ Continue
│  ├─ No? → Install from Play Store
│  └─ No payment method? → Add card in Google Pay
│
└─ Check 5: Flutter logs showing correct platform?
   ├─ Logs show "Platform: ANDROID"? → YES ✓ All good
   ├─ Shows "Platform: IOS"? → Device is iOS (use payment_link)
   └─ Shows "Platform Pay Supported: false"? → Update Google Play Services
```

