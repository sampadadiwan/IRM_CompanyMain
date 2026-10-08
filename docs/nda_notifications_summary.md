# NDA Notifications & Reminders — Summary

## Instant Notifications (triggered by actions)

| # | Event | Who gets notified |
|---|-------|-------------------|
| 1 | LP accepts NDA | GP team (notification emails) |
| 2 | Acceptance confirmation | All LP users of that investor |
| 3 | LP declines NDA | GP team |
| 4 | GP revokes an accepted NDA | All LP users of that investor |
| 5 | GP uploads new NDA version | All LPs who accepted the old version (need to re-accept) |

## Automated Reminders (daily check, runs every morning)

| # | Event | Who gets notified |
|---|-------|-------------------|
| 6 | NDA expiring in 7 days | GP team + LP signatories |
| 7 | NDA has expired | GP team + LP signatories |

## Manual Reminder (GP-triggered from dashboard)

| # | Event | Who gets notified |
|---|-------|-------------------|
| 8 | "Send Reminders" button | NDA signatories of all pending investors |

## Additional features built

- **Revocation** — GP can revoke any accepted NDA from the dashboard with optional reason. Revoked LP sees a message to review and re-accept.
- **Revoked status** — visible on dashboard with purple badge, filterable, included in Excel export
