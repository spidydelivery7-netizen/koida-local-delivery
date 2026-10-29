# Staff notification scheduler test

The staging scheduler automatically processed a synthetic paid order after its cancellation window. It produced one shop notification, called the edge worker successfully twice, and scheduled a retry because no device was registered. No notification was falsely recorded as sent.

Both staging feature switches were restored to OFF and verified. Temporary test fixture cleanup remains incomplete because the connector returned an expired-request error. Complete cleanup before the next enabled test.

Actual shopkeeper/rider device delivery, sound, and vibration remain unverified. No live release was performed. Internal fixture identifiers and operational details are deliberately omitted from this public report.
