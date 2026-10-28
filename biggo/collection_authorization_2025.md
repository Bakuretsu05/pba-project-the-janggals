# Signed-in collection authority

Current authority is the project specification, not just account permission:

- Section 3, updated on main in `8827ffa` (team decision 2026-10-27), explicitly
  permits reading BigGo history while signed into a team member's BigGo account.
- Sections 11 and 13, updated in `3531549`, define the September 1-November 25
  window, tracking coverage, retained flagged listings and acceptance checks.
- The team leader confirmed these changes in PR #11 comments 6445197409,
  6446252989 and 6446598452. No additional team scope decision is pending.

The user separately authorized their own account and manually signed in on Oct 25
and again in ordinary Chrome for the Oct 28 targeted recovery. Their earlier
statement reporting team approval was user-reported at that time; the later merged
specification is now independent documented authority. The original October 25
partial-delivery no-login decision is historical and does not override current main.

No passwords, cookies, JWTs or session tokens are requested, extracted, transferred
between browser contexts or committed. The four Oct 28 history requests ran once
per exact ID in the user's signed-in ordinary Chrome tab, with at least 5.2 seconds
between starts. Chrome's console warning was handled manually by the user; the
agent did not dismiss it. All four responses were HTTP 200 and are saved as public
product/price evidence, with actual Taiwan collection dates.

The old signed-out HTTP 429 response is retained in `access_blocker_2025.json`.
Its action describes the current signed-in policy. It prevents accidental use of
the legacy signed-out collector; it is not a prohibition on approved signed-in work.
