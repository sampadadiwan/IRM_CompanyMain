# Business rules — worked examples

Each row has a Cucumber scenario in `features/mobile/mobile_multi_site.feature` with an
`# <ID> — <kind>: …` comment, unless marked *app* (checked in the web build run, see tasks 3.x).

Shared setup: Rahul (`rahul@sharmafo.in`) of Sharma Family Office; fund managers **Arka Capital**
(Arka Growth Fund I, Calls 1–3, Call 3 pending ₹75 L) and **Beta Partners** (Beta Opportunities,
₹2 Cr committed, no calls). Regions IN (`https://app.caphive.test`) and US
(`https://app.caphive.us.test`).

## Sites (①)

| ID | Kind | Given | When | Then |
|---|---|---|---|---|
| MS-H1 | Happy | SITES has IN and US, CURRENT_SITE=IN | an unsigned phone asks `/sites` | IN India, US US with their URLs; `current` IN |
| MS-E1 | Edge (*app*) | the server has no `/sites` (older deploy) | the site screen loads | the environment's built-in list is shown |

## Region switch (②)

| ID | Kind | Given | When | Then |
|---|---|---|---|---|
| MS-H2 | Happy | Rahul's regions "IN,US" | `/me` | regions IN, US — Profile shows Switch region |
| MS-E2 | Edge | Rahul's regions "IN" | `/me` | regions IN only — no switch shown |
| MS-H3 | Happy | regions "IN,US", signed in on IN | link for US, redeemed on US | 201 session; live phone in region US; no password, no code |
| MS-H4 | Happy (*app*) | the phone already holds a US session | switch to US | no request to IN; instant (82 ms in the local run) |
| MS-H5 | Happy (*app*) | on IN, a US push arrives | tap | the app switches to US, then opens the item |
| MS-X1 | Error | regions "IN" | ask for a link to US | 422 `region_unavailable` |
| MS-E3 | Edge | on IN | ask for a link to IN | 422 `region_unavailable` |
| MS-X2 | Error | a website link (`:login` purpose) for US | redeemed on the phone API in US | 401 `region_switch_failed` |
| MS-X3 | Error | no cross-region secret | ask for a link | 422 `region_unavailable` |
| MS-X4 | Error | a link for US | redeemed on IN | 401 `region_switch_failed` |
| MS-X5 | Error | a link already redeemed | redeemed again | 401 `challenge_spent` |
| MS-E4 | Edge | Rahul deactivated in US | redeem a valid link on US | 401 `invalid_credentials` |
| MS-E5 | Edge (*app*) | signed in on IN and US | Sign out | both regions' phone sessions revoked |

## One fund manager (③)

| ID | Kind | Given | When | Then |
|---|---|---|---|---|
| MF-H3 | Happy | access to Arka and Beta | `/me` | fund_managers "Arka Capital, Beta Partners" (sorted) |
| MF-H1 | Happy | access to Arka and Beta | Home with no pick | Arka's cards only; `fund_manager_id` = Arka |
| MF-H2 | Happy | access to Arka and Beta | Home for Beta | Beta's card only; To do empty (Arka's Call 3 gone) |
| MF-E1 | Edge | Gamma exists, no access | Home for Gamma | falls back to Arka |
| MF-E2 | Edge | no fund manager at all | Home | `fund_manager_id` nil; empty Home |
| MF-E3 | Edge (*app*) | access to Arka only | Home | name shown as a label, no dropdown |
| MF-H4 | Happy | Arka doc "Arka Statement", Beta doc "Beta Statement" | Documents for Beta | Beta Statement listed; Arka Statement not |
| MF-H5 | Happy | an alert from Arka | notifications JSON; push for Call 3 | `sender_id` = Arka; push data has `fund_manager_id` = Arka and `region` = IN |
| MF-E4 | Edge (*app*) | picked Beta on IN | reopen the app; switch to US and back | IN still on Beta; US has its own pick |
