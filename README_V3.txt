KOIDA LOCAL DELIVERY - MASTER V3 EMAIL RECOVERY

Includes:
- index.html
- admin.html
- config.js
- shopkeeper.html
- reset-password.html

What changed:
- New customer signup now collects a real email address.
- New customer login uses Email + 6-digit PIN.
- Forgot PIN sends a Supabase recovery email.
- Recovery email redirects to /reset-password.html.
- reset-password.html lets the customer set a new 6-digit PIN.
- Legacy Mobile Login remains available for older mobile-only test accounts.
- Existing Sold Out / Available behavior and shopkeeper panel are preserved.

Supabase already configured:
- Site URL: https://cheery-marshmallow-1e366d.netlify.app
- Redirect URL: https://cheery-marshmallow-1e366d.netlify.app/reset-password.html
