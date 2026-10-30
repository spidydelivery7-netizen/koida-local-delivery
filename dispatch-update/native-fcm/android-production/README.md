# HUNKART production staff Android source

This is a release build template for the existing shopkeeper and delivery partner application IDs. The old APK signing private keys have not been recovered, so these builds require uninstalling the old APK and signing in again. Shop, rider, order and password data remain on the production Supabase server. Do not uninstall old apps until the signed candidates have passed install and live-flow tests.

The production GitHub Actions workflow refuses staging Firebase JSON, missing permanent keystore secrets, or package IDs other than `com.hunkart.shopkeeper` and `com.hunkart.deliverypartner`. Never commit `google-services.json` or a keystore. Customer Play AAB is a separate release.
