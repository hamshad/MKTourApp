package com.mokshasolutions.mktours

import android.app.Activity
import android.content.Intent
import android.util.Log
import com.google.android.gms.common.api.ApiException
import com.google.android.gms.wallet.*
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject

class GooglePayHandler(private val activity: Activity) : MethodChannel.MethodCallHandler {

  companion object {
    private const val TAG = "GooglePayHandler"
    private const val LOAD_PAYMENT_DATA_REQUEST_CODE = 991
    private const val CHANNEL = "com.mokshasolutions.mktours/googlepay"
  }

  private var paymentsClient: PaymentsClient? = null
  private var pendingResult: MethodChannel.Result? = null
  private var isTestEnv: Boolean = false

  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    when (call.method) {
      "isGooglePayAvailable" -> checkGooglePayAvailable(call, result)
      "requestPayment" -> requestPayment(call, result)
      else -> result.notImplemented()
    }
  }

  private fun getPaymentsClient(testEnv: Boolean): PaymentsClient {
    if (paymentsClient == null || isTestEnv != testEnv) {
      isTestEnv = testEnv
      val environment =
              if (testEnv) {
                WalletConstants.ENVIRONMENT_TEST
              } else {
                WalletConstants.ENVIRONMENT_PRODUCTION
              }
      Log.d(
              TAG,
              "Creating PaymentsClient with environment: ${if (testEnv) "TEST" else "PRODUCTION"}"
      )

      paymentsClient =
              Wallet.getPaymentsClient(
                      activity,
                      Wallet.WalletOptions.Builder().setEnvironment(environment).build()
              )
    }
    return paymentsClient!!
  }

  private fun checkGooglePayAvailable(call: MethodCall, result: MethodChannel.Result) {
    val testEnv = call.argument<Boolean>("testEnv") ?: false
    Log.d(TAG, "Checking Google Pay availability (testEnv: $testEnv)")

    val client = getPaymentsClient(testEnv)
    val request = IsReadyToPayRequest.fromJson(getIsReadyToPayRequest().toString())

    client.isReadyToPay(request).addOnCompleteListener { task ->
      try {
        val isReady = task.getResult(ApiException::class.java)
        Log.d(TAG, "Google Pay available: $isReady")
        result.success(isReady)
      } catch (e: ApiException) {
        Log.e(TAG, "Google Pay check failed: ${e.message}", e)
        result.success(false)
      }
    }
  }

  private fun requestPayment(call: MethodCall, result: MethodChannel.Result) {
    val amount = call.argument<String>("amount") ?: "0.00"
    val currencyCode = call.argument<String>("currencyCode") ?: "GBP"
    val merchantName = call.argument<String>("merchantName") ?: "MK Tours"
    val stripePublishableKey = call.argument<String>("stripePublishableKey") ?: ""
    val testEnv = call.argument<Boolean>("testEnv") ?: false

    Log.d(TAG, "═══════════════════════════════════════════════════")
    Log.d(TAG, "💳 [GooglePay] NATIVE: Requesting payment")
    Log.d(TAG, "💳 [GooglePay] Amount: $amount $currencyCode")
    Log.d(TAG, "💳 [GooglePay] Merchant: $merchantName")
    Log.d(TAG, "💳 [GooglePay] TestEnv: $testEnv")
    Log.d(TAG, "💳 [GooglePay] Stripe key present: ${stripePublishableKey.isNotEmpty()}")

    pendingResult = result
    val client = getPaymentsClient(testEnv)

    val paymentDataRequest =
            getPaymentDataRequest(
                    amount = amount,
                    currencyCode = currencyCode,
                    merchantName = merchantName,
                    stripePublishableKey = stripePublishableKey
            )

    val request = PaymentDataRequest.fromJson(paymentDataRequest.toString())
    Log.d(TAG, "💳 [GooglePay] PaymentDataRequest: $paymentDataRequest")

    AutoResolveHelper.resolveTask(
            client.loadPaymentData(request),
            activity,
            LOAD_PAYMENT_DATA_REQUEST_CODE
    )
  }

  fun handleActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
    if (requestCode != LOAD_PAYMENT_DATA_REQUEST_CODE) return false

    when (resultCode) {
      Activity.RESULT_OK -> {
        data?.let {
          val paymentData = PaymentData.getFromIntent(it)
          val paymentInfo = paymentData?.toJson()
          Log.d(TAG, "✅ [GooglePay] Payment data received")

          if (paymentInfo != null) {
            try {
              val json = JSONObject(paymentInfo)
              val token =
                      json.getJSONObject("paymentMethodData")
                              .getJSONObject("tokenizationData")
                              .getString("token")
              Log.d(TAG, "✅ [GooglePay] Token extracted successfully")
              pendingResult?.success(
                      mapOf("success" to true, "token" to token, "paymentInfo" to paymentInfo)
              )
            } catch (e: Exception) {
              Log.e(TAG, "❌ [GooglePay] Token parse error: ${e.message}")
              pendingResult?.success(
                      mapOf(
                              "success" to false,
                              "error" to "Failed to parse payment token: ${e.message}"
                      )
              )
            }
          } else {
            Log.e(TAG, "❌ [GooglePay] Payment info is null")
            pendingResult?.success(mapOf("success" to false, "error" to "Payment data was null"))
          }
        }
                ?: run {
                  pendingResult?.success(
                          mapOf("success" to false, "error" to "No data returned from Google Pay")
                  )
                }
      }
      Activity.RESULT_CANCELED -> {
        Log.d(TAG, "⚠️ [GooglePay] Payment cancelled by user")
        pendingResult?.success(mapOf("success" to false, "error" to "cancelled"))
      }
      AutoResolveHelper.RESULT_ERROR -> {
        val status = AutoResolveHelper.getStatusFromIntent(data)
        Log.e(TAG, "❌ [GooglePay] Error: ${status?.statusMessage} (code: ${status?.statusCode})")
        pendingResult?.success(
                mapOf(
                        "success" to false,
                        "error" to
                                "Google Pay error: ${status?.statusMessage ?: "Unknown error"} (${status?.statusCode})"
                )
        )
      }
    }
    pendingResult = null
    return true
  }

  // ── Google Pay JSON Request Builders ────────────────────────────

  private fun getBaseCardPaymentMethod(): JSONObject {
    return JSONObject().apply {
      put("type", "CARD")
      put(
              "parameters",
              JSONObject().apply {
                put("allowedAuthMethods", JSONArray(listOf("PAN_ONLY", "CRYPTOGRAM_3DS")))
                put(
                        "allowedCardNetworks",
                        JSONArray(listOf("AMEX", "DISCOVER", "MASTERCARD", "VISA"))
                )
              }
      )
    }
  }

  private fun getCardPaymentMethod(stripePublishableKey: String): JSONObject {
    val base = getBaseCardPaymentMethod()
    base.put(
            "tokenizationSpecification",
            JSONObject().apply {
              put("type", "PAYMENT_GATEWAY")
              put(
                      "parameters",
                      JSONObject().apply {
                        put("gateway", "stripe")
                        put("stripe:version", "2024-06-20")
                        put("stripe:publishableKey", stripePublishableKey)
                      }
              )
            }
    )
    return base
  }

  private fun getIsReadyToPayRequest(): JSONObject {
    return JSONObject().apply {
      put("apiVersion", 2)
      put("apiVersionMinor", 0)
      put("allowedPaymentMethods", JSONArray().apply { put(getBaseCardPaymentMethod()) })
    }
  }

  private fun getPaymentDataRequest(
          amount: String,
          currencyCode: String,
          merchantName: String,
          stripePublishableKey: String
  ): JSONObject {
    return JSONObject().apply {
      put("apiVersion", 2)
      put("apiVersionMinor", 0)
      put(
              "allowedPaymentMethods",
              JSONArray().apply { put(getCardPaymentMethod(stripePublishableKey)) }
      )
      put(
              "transactionInfo",
              JSONObject().apply {
                put("totalPrice", amount)
                put("totalPriceStatus", "FINAL")
                put("currencyCode", currencyCode)
                put("countryCode", "GB")
              }
      )
      put("merchantInfo", JSONObject().apply { put("merchantName", merchantName) })
    }
  }
}
