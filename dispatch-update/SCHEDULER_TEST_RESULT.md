# Staff notification status

Staging cron automatically processed a synthetic paid shop order and called the edge worker successfully twice. Missing-device delivery produced retries, not false sent status or duplicate notices.

Temporary test order, items, shop/product/staff and synthetic accounts have now been deleted and cleanup verified. Both feature switches remain OFF. Expired invocation retention is implemented in bounded batches and four rollback assertions passed.

Existing automated evidence: 86 workflow checks, 35 worker/service-worker checks, four nonce authorization checks. No actual staff-device order delivery has passed yet.

## Newly confirmed APK gap
The repository shopkeeper and delivery Android build definitions currently create WebView wrappers with network/location support. They contain no native push receiver, Firebase Messaging integration, notification channel or Android notification permission request. Browser Web Push success must not be presented as APK background notification success.

Before completion: configure native messaging for staff APKs, bind device tokens to authenticated staff safely, integrate delivery with the backend, build isolated staging APKs, and verify real devices foreground/background/locked. Firebase project configuration is not present in the repository. Customer automatic background retry also remains pending; the staff scheduler alone does not implement it.

All code remains on the draft branch. No live app, payment or Play release changes were made.
