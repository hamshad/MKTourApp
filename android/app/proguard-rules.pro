# Proguard/R8 rules for release builds.
#
# Google Maps SDK + Play services: release minify otherwise strips/renames
# platform-view classes -> blank/grey tiles on signed builds only (debug unaffected).
-keep class com.google.android.gms.maps.** { *; }
-keep class com.google.maps.** { *; }
-keep class com.google.android.libraries.maps.** { *; }
-keep class io.flutter.plugins.googlemaps.** { *; }
-keep class com.google.android.gms.common.** { *; }
-keep class com.google.android.gms.location.** { *; }
-dontwarn com.google.android.gms.maps.**
-dontwarn com.google.maps.**
# Stripe Android SDK: some optional push provisioning classes may be absent depending
# on the Stripe SDK variant/version; suppress R8 missing class warnings.
-dontwarn com.stripe.android.pushProvisioning.PushProvisioningActivity$g
-dontwarn com.stripe.android.pushProvisioning.PushProvisioningActivityStarter$Args
-dontwarn com.stripe.android.pushProvisioning.PushProvisioningActivityStarter$Error
-dontwarn com.stripe.android.pushProvisioning.PushProvisioningActivityStarter
-dontwarn com.stripe.android.pushProvisioning.PushProvisioningEphemeralKeyProvider
