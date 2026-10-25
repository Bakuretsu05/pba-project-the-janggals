# Authenticated 2025 collection authorization

On 2026-10-25 the user confirmed in this task: “Yes, the team has explicitly
approved authenticated BigGo history collection using my own account.”

The user manually signed into BigGo in the in-app browser and confirmed successful
login. The previously blocked APPL-019 momo history then displayed its complete
two-year table. This authorizes using that ordinary browser session for the 2025
collection and independent checks. The project specification itself is unchanged.

No passwords, cookies, JWTs or session tokens are requested, extracted, copied or
committed. The original unauthenticated HTTP 429 evidence remains retained.
The fresh-session HTTP collector stays blocked; the authorized continuation uses
ordinary UI history controls and saves only public product/price-table evidence.
The browser keeps its ordinary identity; its authenticated session is not moved
into the separate HTTP collector or the failed Chrome login profile.

Missing exact item IDs are recorded as search failures, with no substitution of
another product. Any authentication refusal or CAPTCHA requires stopping for the
user. Controlled BigGo actions are spaced at least 5.2 seconds apart, with immediate
local checkpoints after each listing.
