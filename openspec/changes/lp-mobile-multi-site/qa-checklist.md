# QA checklist — staging

Staging IN `https://dev.altconnects.com`, staging US `https://dev.altconnects.us`. Demo data:
`RAILS_ENV=staging bin/rails mobile:seed_demo` (IN), then give the demo user `regions = "IN,US"` in
both regions.

| ☐ | ID | Check | Steps | Expected |
|---|---|---|---|---|
| ☐ | MS-H1 | Site screen | Install the staging APK, open | Staging selected; India and US listed with their addresses |
| ☐ | — | Hidden in production | Pick CapHive | Only India / US (production) |
| ☐ | MF-H1 | Default fund manager | Sign in as the demo user on India | Picker shows the first fund manager by name; only its funds |
| ☐ | MF-H2 | Pick | Pick the other fund manager | Home, Documents, Alerts change to it |
| ☐ | MF-E4 | Remembered | Close and reopen the app | Same fund manager |
| ☐ | MS-H3 | Switch region | Profile → Switch region → US | No password asked; Home shows US data |
| ☐ | MS-H4 | Switch back | Profile → India | Instant |
| ☐ | MS-E2 | One-region user | Sign in as a user with regions "IN" | No Switch region card |
| ☐ | MS-E5 | Sign out | Sign out | Website › Profile › Mobile Devices in IN and US both show the phone signed out |
| ☐ | MS-H5 | Push from US | With push configured, send a US capital call notice; tap it while on India | App moves to US and opens the call |
