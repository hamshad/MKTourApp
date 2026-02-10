# Google Pay + Stripe Integration Setup Guide

## 📱 Overview
This guide covers the complete setup for Google Pay on Android devices with Stripe integration.

---

## 🔧 Frontend (Flutter) - COMPLETED ✅

### What's Already Configured:

1. **StripeService** (`lib/core/services/stripe_service.dart`)
   - ✅ Proper platform detection (Android/iOS)
   - ✅ Google Pay prioritized for Android
   - ✅ Apple Pay prioritized for iOS
   - ✅ Comprehensive logging for debugging

2. **Payment Flow** (`lib/features/ride/ride_assigned_screen.dart`)
   - ✅ Android shows "Pay Online" button
   - ✅ iOS shows "Payment Link" button
   - ✅ Cash available for both
   - ✅ Sends `pay_online` method to backend for Android

3. **Dependencies** (`pubspec.yaml`)
   - ✅ flutter_stripe: ^11.3.0

---

## 🚀 Backend Requirements (IMPORTANT!)

### 1. **Payment Intent Configuration**

When user selects "Pay Online" (Android), your backend must:

```json
POST /api/v1/rides/{rideId}/select-payment-method
Request: {
  "paymentMethod": "pay_online"
}

Response: {
  "success": true,
  "data": {
    "ride": {
      "paymentMethod": "stripe",
      "clientSecret": "pi_3ABC123_secret_xyz789",
      "amount": 2500,  // in pence (£25.00)
      "currency": "GBP",
      "status": "driver_arrived"
    }
  }
}
```

### 2. **Stripe Dashboard Setup** (CRITICAL!)

**Location:** https://dashboard.stripe.com

#### Step 1: Enable Google Pay
1. Go to **Settings** → **Payment methods**
2. Enable **Google Pay** (toggle it ON)
3. Ensure it shows as "Active"

#### Step 2: Add Your Android App
1. Go to **Settings** → **Customer accounts** or **Google integrations**
2. Add your Android app package ID: `com.mokshasolutions.mktours`
3. Configure merchant identifier if required

#### Step 3: Configure PaymentIntent
When creating PaymentIntent, include:
```
payment_method_types: ['card', 'google_pay']  // MUST include both
currency: 'gbp'
amount: [in pence]
```

#### Step 4: Verify Webhook
- Endpoint: Configure to listen for `charge.succeeded` events
- Use `pi_*` payment intent IDs to match rides

### 3. **Backend Code Changes Needed**

Your backend's payment method selection endpoint should:

```typescript
// Example (Node.js/Express)
router.post('/rides/:rideId/select-payment-method', async (req, res) => {
  const { paymentMethod } = req.body;

  if (paymentMethod === 'pay_online') {
    try {
      // Get ride details from database
      const ride = await Ride.findById(req.params.rideId);
      
      // Create Stripe PaymentIntent
      const paymentIntent = await stripe.paymentIntents.create({
        amount: Math.round(ride.fare * 100), // Convert to pence
        currency: 'gbp',
        payment_method_types: ['card', 'google_pay'], // CRITICAL!
        metadata: {
          rideId: ride._id.toString(),
          userId: ride.user.toString(),
        },
      });

      // Save payment intent ID to ride
      ride.stripePaymentIntentId = paymentIntent.id;
      await ride.save();

      // Return client secret to Flutter
      return res.json({
        success: true,
        data: {
          ride: {
            paymentMethod: 'stripe',
            clientSecret: paymentIntent.client_secret,
            amount: ride.fare,
            currency: 'GBP',
            status: ride.status,
          }
        }
      });
    } catch (error) {
      return res.status(400).json({ 
        success: false, 
        message: error.message 
      });
    }
  }
  // ... handle other payment methods (cash, payment_link)
});
```

### 4. **Testing**

**Test Card Numbers:**
- Google Pay: Use any Visa/Mastercard test card
  - Visa: `4242 4242 4242 4242`
  - Mastercard: `5555 5555 5555 4444`
- Exp: Any future date (e.g., 12/25)
- CVC: Any 3 digits (e.g., 123)

**Using Test Mode:**
- In `StripeService.processPayment()`, change `testEnv: false` to `testEnv: true`
- Rebuild and test
- Change back to `false` for production

---

## 🐛 Debugging

### Check Logs
When payment is initiated, you should see:
```
💳 [Stripe] ============ PAYMENT INITIALIZATION ============
💳 [Stripe] Platform: ANDROID
💳 [Stripe] Client Secret: pi_3ABC123...
💳 [Stripe] Platform Pay Supported: true
💳 [Stripe] 🤖 ANDROID DETECTED - Configuring Google Pay
💳 [Stripe] ✅ Google Pay payment sheet initialized
💳 [Stripe] 📱 Opening payment sheet...
```

### If Google Pay Doesn't Show

**Possible Issues:**

1. **Backend not sending `payment_method_types: ['card', 'google_pay']`**
   - Solution: Update backend PaymentIntent creation
   - Check: Backend logs for PaymentIntent creation

2. **Device doesn't have Google Pay app**
   - Solution: Install Google Pay app from Play Store
   - Device must have a payment method added in Google Pay

3. **Stripe not configured in dashboard**
   - Solution: Enable Google Pay in Stripe Dashboard
   - Check: Dashboard > Settings > Payment methods

4. **Wrong currency or amount format**
   - Solution: Ensure amount is in pence (2500 = £25.00)
   - Ensure currency is 'gbp' (lowercase)

---

## ✅ Verification Checklist

- [ ] Backend returns `paymentMethod: 'stripe'` with `clientSecret`
- [ ] Backend includes `payment_method_types: ['card', 'google_pay']` in PaymentIntent
- [ ] Google Pay enabled in Stripe Dashboard
- [ ] Device has Google Pay app installed
- [ ] Device has a payment method in Google Pay
- [ ] Flutter logs show "Platform: ANDROID" and "Platform Pay Supported: true"
- [ ] Payment sheet opens with Google Pay button visible
- [ ] Test payment works end-to-end

---

## 📞 Support

If Google Pay still doesn't show:
1. Check Flutter logs (grep for `💳 [Stripe]`)
2. Check backend logs for PaymentIntent creation
3. Verify Stripe Dashboard configuration
4. Test on physical device (emulators sometimes have issues)

