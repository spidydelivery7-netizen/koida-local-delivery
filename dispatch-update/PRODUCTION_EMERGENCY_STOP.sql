-- HUNKART staff dispatch emergency stop, preserving all order/payment/refund records.
-- Execute only on the matching production project after checking the project ref.
-- This file is not run automatically.
BEGIN;
DO $guard$
BEGIN
 IF to_regnamespace('hunkart_dispatch') IS NULL THEN
  RAISE EXCEPTION 'Dispatch schema missing; no rollout to disable';
 END IF;
 IF to_regclass('hunkart_dispatch.settings') IS NULL OR
    to_regclass('hunkart_dispatch.staff_notification_settings') IS NULL THEN
  RAISE EXCEPTION 'Dispatch settings missing; stop and inspect';
 END IF;
END $guard$;
UPDATE hunkart_dispatch.settings SET enabled=false WHERE singleton=true;
UPDATE hunkart_dispatch.staff_notification_settings SET enabled=false WHERE singleton=true;
COMMIT;
-- Keep pending/refund/order rows intact. Restore previous staff pages/admin UI separately.
-- Do not drop schema or revert actor constraint while shopkeeper cancellation cases may exist.
