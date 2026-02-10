# Google Pay Implementation - Complete Checklist

## ✅ What's Been Implemented (Flutter Side)

### 1. Payment Selection Modal
- [x] Android: Shows "Pay Online" button (instead of "Payment Link")
- [x] iOS: Shows "Payment Link" button
- [x] Both: Shows "Cash" option
- [x] Sends correct method to backend: `pay_online` for Android

### 2. Stripe Service Configuration
- [x] Platform detection (Android/iOS/Other)
- [x] Google Pay configured for Android with:
  - Merchant country: GB
  - Currency: GBP
  - Payment method order: google_pay first, then card
- [x] Apple Pay configured for iOS
- [x] Comprehensive logging for debugging

### 3. Error Handling
- [x] Try-catch block for payment failures
- [x] User-friendly error messages
- [x] Re-opens payment selection modal on failure
- [x] Proper state management

### 4. Display Labels
- [x] Android shows "Paid Online" after successful payment
- [x] iOS shows "Card" after successful payment
- [x] Cash shows "Cash" for both platforms

---

## 🔴 What You MUST Check on Backend

### 1. PaymentIntent Creation
When backend receives `paymentMethod: "pay_online"`, it must:

```
✅ Create Stripe PaymentIntent with:
   - payment_method_types: ['card', 'google_pay']  ← CRITICAL!
   - currency: 'gbp'
   - amount: [in pence]
   - metadata: { rideId, userId, ... }

✅ Return response with:
   - paymentMethod: 'stripe'
   - clientSecret: 'pi_..._secret_...'
   - amount: fare
   - currency: 'GBP'
```

### 2. Stripe Dashboard
- [ ] Go to: https://dashboard.stripe.com
- [ ] Settings → Payment methods
- [ ] **Enable Google Pay** (toggle it ON)
- [ ] Verify it shows as "Active"

### 3. Test Backend Endpoint
```bash
curl -X POST http://your-backend/api/v1/rides/{rideId}/select-payment-method \
  -H "Content-Type: application/json" \
  -d '{
    "paymentMethod": "pay_online"
  }'
```

Should return:
```json
{
  "success": true,
  "data": {
    "ride": {
      "paymentMethod": "stripe",
      "clientSecret": "pi_..._secret_...",
      "amount": 2500,
      "currency": "GBP"
    }
  }
}
```

---

## 🔍 Testing on Android Device

### Step 1: Ensure Setup
- [ ] Device has Google Play Services updated
- [ ] Device has Google Pay app installed
- [ ] Google Pay has a payment method configured (even test card)

### Step 2: Test Payment Flow
1. Open app on Android device
2. Proceed to ride payment selection
3. Tap "Pay Online"
4. Verify logs show:
   ```
   💳 [Stripe] Platform: ANDROID
   💳 [Stripe] Platform Pay Supported: true
   💳 [Stripe] 🤖 ANDROID DETECTED - Configuring Google Pay
   💳 [Stripe] ✅ Google Pay payment sheet initialized
   ```
5. Payment sheet should open with **Google Pay** button visible
6. Should NOT see Stripe Link option

### Step 3: Verify Logs
Look for these logs in **Flutter console**:
```
💳 [Stripe] ============ PAYMENT INITIALIZATION ============
💳 [Stripe] Platform: ANDROID
💳 [Stripe] Platform Pay Supported: true
💳 [Stripe] 🤖 ANDROID DETECTED - Configuring Google Pay
💳 [Stripe] Setting up Google Pay with merchant country: GB
💳 [Stripe] ✅ Google Pay payment sheet initialized
💳 [Stripe] 📱 Opening payment sheet...
✅ [Stripe] Payment successful!
```

### Step 4: Test Scenarios
- [ ] Test with real Google Pay
- [ ] Test with test payment method
- [ ] Test payment cancellation
- [ ] Test payment failure

---

## ⚠️ Common Issues & Fixes

### Issue 1: Still Seeing "Link" and "Card" Instead of Google Pay

**Cause:** Backend not including `payment_method_types: ['card', 'google_pay']`

**Fix:** 
1. Check backend code for PaymentIntent creation
2. Ensure it includes both 'card' and 'google_pay' in payment_method_types
3. Restart backend service
4. Test again

**Verify with:**
```bash
# Check Stripe PaymentIntent directly
curl https://api.stripe.com/v1/payment_intents/{PAYMENT_INTENT_ID} \
  -u sk_test_YOUR_KEY:
```

### Issue 2: Google Pay Supported = false

**Cause:** Device missing Google Play Services or Google Pay app

**Fix:**
1. Update Google Play Services: Play Store → My apps → Updates
2. Install Google Pay app from Play Store
3. Add a payment method in Google Pay
4. Test again

### Issue 3: Google Pay Button Not Clickable

**Cause:** No payment method in Google Pay account

**Fix:**
1. Open Google Pay app
2. Add a test card or real card
3. Ensure card is set as default
4. Test again

---

## 📋 Files Modified/Created

### Modified:
- [lib/features/ride/ride_assigned_screen.dart](lib/features/ride/ride_assigned_screen.dart#L2290)
  - Updated Android payment option to send `pay_online` method
  - Better error handling

- [lib/core/services/stripe_service.dart](lib/core/services/stripe_service.dart#L60)
  - Proper Google Pay configuration for Android
  - Improved logging
  - Platform-specific payment sheet setup

### Created:
- [GOOGLE_PAY_STRIPE_SETUP.md](GOOGLE_PAY_STRIPE_SETUP.md)
  - Complete setup and debugging guide

---

## 🚀 Next Steps

1. **Verify Backend Configuration**
   - Check that PaymentIntent includes `payment_method_types: ['card', 'google_pay']`
   - Test endpoint with curl/Postman

2. **Verify Stripe Dashboard**
   - Enable Google Pay in Payment methods
   - Verify settings are saved

3. **Test on Android Device**
   - Run the app on real Android device
   - Monitor Flutter logs
   - Try a test payment

4. **Monitor Logs**
   - Share the Flutter logs if Google Pay still doesn't show
   - Check backend logs for PaymentIntent creation

---

## 📞 Troubleshooting

If Google Pay still doesn't appear:

1. **Collect Debug Info:**
   - [ ] Flutter logs (grep for `💳 [Stripe]`)
   - [ ] Backend logs (show PaymentIntent creation)
   - [ ] Stripe Dashboard verification (Google Pay enabled?)
   - [ ] Device info (has Google Play Services, Google Pay app)

2. **Run Verification:**
   - [ ] Backend endpoint test (see "Test Backend Endpoint" above)
   - [ ] Check response has `paymentMethod: 'stripe'` and `clientSecret`
   - [ ] Verify Stripe Dashboard settings

3. **Share Logs:**
   - Share Flutter console logs when payment selection happens
   - Share backend logs showing PaymentIntent creation
   - Confirm Stripe Dashboard configuration

