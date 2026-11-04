# Zoho Sign eSign — operations guide

For CapHive support and developers. How a company connects its own Zoho Sign account, how
CapHive's own (platform) account is configured per environment, how to run the developer-assisted
QA checks, and what to do when something goes wrong.

Design and decisions: `openspec/changes/zoho-esign-production-ready/` (proposal, design, lld).

## How accounts are chosen

- Every company whose eSign provider is **Zoho** signs through **CapHive's platform account** until
  it connects its own.
- CapHive support can connect the company's **own Zoho Sign account** on the company page ›
  **Zoho eSign** panel. Company admins do not see the panel.
- **Cutover:** documents sent at or after the "Connected on" moment use the company's account.
  Documents sent before keep using CapHive's account for every later action (status check,
  reminder, extend, cancel, download). Reconnecting does not move the cutover.
- Disconnecting is refused while any document sent on the company's account is still out for
  signature.

## Zoho regions

Pick the region from the address of the client's Zoho account.

| Region | Zoho Sign address | Accounts address |
|---|---|---|
| United States | sign.zoho.com | accounts.zoho.com |
| Europe | sign.zoho.eu | accounts.zoho.eu |
| India | sign.zoho.in | accounts.zoho.in |
| Japan | sign.zoho.jp | accounts.zoho.jp |
| Australia | sign.zoho.com.au | accounts.zoho.com.au |
| Canada | sign.zohocloud.ca | accounts.zohocloud.ca (verify before first use — QA P2) |
| Saudi Arabia | sign.zoho.sa | accounts.zoho.sa |
| United Kingdom | sign.zoho.uk | accounts.zoho.uk |
| Singapore | sign.zoho.sg | accounts.zoho.sg |
| UAE | sign.zoho.ae | accounts.zoho.ae |

## Connecting a company's own account (Option A — Self Client)

The client does the Zoho steps (1–3 and 6–7) and CapHive support does the CapHive steps (4–5), on a
call so the grant code can be used at once. It lasts about ten minutes and works once.

1. **Find the region.** In Zoho Sign, note the address bar (`sign.zoho.com` = United States, etc.).
2. **Create a Self Client.** Zoho API console (`https://api-console.zoho.<domain>`) › **Add Client**
   › **Self Client** › Create. Zoho shows a **Client ID** and **Client Secret**.
3. **Generate a grant code.** Self Client › **Generate Code**, scopes exactly
   `ZohoSign.documents.CREATE,ZohoSign.documents.READ,ZohoSign.documents.UPDATE`, duration
   10 minutes, any description. Zoho shows the grant code.
4. **Connect in CapHive.** Company page › **Zoho eSign** › pick the region, paste Client ID, Client
   Secret and the grant code › **Connect**. The panel shows **Connected** and "Connected on".
5. **Copy the webhook details.** On the panel, copy the **Webhook address** and click **Show webhook
   secret** — it is shown once only.
6. **Create the webhook in Zoho.** Zoho Sign › Settings › Developer settings › Webhooks › Create
   webhook: paste the address, tick **HMAC signature** and paste the secret, tick the events
   *Sent, Signed by a recipient, Completed by all, Declined, Expires, Recalled* (and *Forwarded*
   if offered), save.
7. **Test.** In Zoho, **Test Url** on the webhook. Zoho shows success and the CapHive panel's
   "Last update" changes to now.

Messages support may see on Connect:

| Message starts with | Cause | Fix |
|---|---|---|
| "Zoho did not accept the grant code" | Code expired (≈10 min) or already used | Generate a new code (step 3) and connect within 10 minutes |
| "Zoho did not recognise this Client ID in the <region> region" | Wrong region | Pick the region matching the Zoho address (step 1) |
| "Zoho did not accept the Client Secret" | Secret mistyped | Copy it again from the Self Client |
| "Zoho could not be reached" | Zoho down / network | Try again in a few minutes |

**Option B (future, not built):** a one-click "Connect with Zoho" OAuth redirect. It needs a
CapHive-registered Zoho app (server-based client) in each of the ten regions, with redirect URIs
per CapHive host. It removes steps 2–3 for clients. Revisit if Self Client setup becomes a support
burden.

## CapHive's platform account per environment

| Setting | Where | Notes |
|---|---|---|
| `ZOHO_CLIENT_ID`, `ZOHO_CLIENT_SECRET`, `ZOHO_REFRESH_TOKEN` | Rails credentials of the environment | CapHive's Self Client in CapHive's Zoho org (India) |
| `ZOHO_WEBHOOK_SECRET` | Rails credentials | **Required in staging and production** — without it the shared webhook refuses every Zoho update |
| `ZOHO_REGION` | env var, optional | Defaults to `in` |
| `active_record_encryption` | Rails credentials | Needed in every deployed environment before the company-connection release (secrets are stored encrypted) |

Getting the platform refresh token (once per environment, from a Rails console in that
environment, after generating a grant code for CapHive's Self Client as in step 3):

```ruby
creds = Rails.application.credentials
ZohoSignClient.exchange_grant_code(region: "in", client_id: creds[:ZOHO_CLIENT_ID],
                                   client_secret: creds[:ZOHO_CLIENT_SECRET], code: "1000.<grant code>")
# => the refresh token; store it as ZOHO_REFRESH_TOKEN in that environment's credentials
```

The platform webhook in CapHive's Zoho account points at `https://<host>/documents/signature_progress`
with HMAC on and the same secret as `ZOHO_WEBHOOK_SECRET`.

### Rollout checklist

Release 1 (platform hardening):
- [ ] `ZOHO_CLIENT_ID`, `ZOHO_CLIENT_SECRET`, `ZOHO_REFRESH_TOKEN` present in each environment that
      uses Zoho (today: development, staging.in; missing: staging.us, production.in, production.us)
- [ ] `ZOHO_WEBHOOK_SECRET` added to credentials **and** HMAC enabled with the same secret on
      CapHive's Zoho webhook — in the same deploy
- [ ] `ZOHO_SIGN_URL` / `ZOHO_ACCOUNTS_URL` are no longer read (removed from `.env.*`)
- [ ] QA pre-release checks P1–P4 on staging

Release 2 (company connections):
- [ ] `active_record_encryption` keys present in staging.in, staging.us, production.in, production.us
- [ ] Migration `20261029120000_create_zoho_sign_connections` runs before the code (adds an online
      index on `documents.provider_doc_id`)

Rollback: release 1 — revert code, no data. Release 2 — revert code; the new table can stay
unused, companies fall back to CapHive's account.

## Aadhaar and e-stamping

Not supported through Zoho yet. A send with an Aadhaar signer or stamp papers is refused, because
Zoho would otherwise collect a plain electronic signature with no stamp. The forms hide both options
for Zoho companies, so this only reaches companies that moved from Digio with existing settings.

Support clears them from the console, on the document and on its template so new documents stop
copying them:

```ruby
doc = Document.find(<document or template id>)
doc.e_signatures.where(signature_type: "Aadhaar").update_all(signature_type: "Electronic")
doc.stamp_papers.destroy_all
```

Future improvement, once there is a working paid Zoho account (both need a paid plan and the India
data centre; neither works on a trial):

- **Aadhaar:** send `allowed_cloud_provider_ids: [25]` on each Aadhaar signer's action. An admin turns
  Aadhaar eSign on in Zoho (Settings › Integrations), and each signing costs 2 credits.
- **E-stamping:** send `estamping_request` on the request (`PUT /api/v1/requests/<id>`). It needs the
  state, document category, both parties' details, consideration amount and duty payer, which our
  stamp papers do not hold, plus credits per stamp. This is a feature of its own.

## Developer-assisted QA

Rows marked *(dev-assisted)* in `qa-checklist.md`. Replace `<host>`, ids and secrets.

**Webhook posts (E27, E31, E32, X18–X22).** Get a company's address and secret from a console:

```ruby
c = ZohoSignConnection.find_by(entity_id: <entity id>)
c.webhook_token   # address: https://<host>/zoho_sign/webhooks/<token>
c.webhook_secret  # console only - never paste into tickets
Document.find(<document id>).provider_doc_id  # the Zoho request id
```

```bash
BODY='{"notifications":{"operation_type":"RequestSigningSuccess","performed_by_email":"rohan@example.com"},"requests":{"request_id":"<request id>"}}'
SIG=$(printf '%s' "$BODY" | openssl dgst -sha256 -hmac "$SECRET" -binary | base64)

# Signed update to a company's address (E27: run it twice; E31: operation_type RequestExpired)
curl -i -X POST "https://<host>/zoho_sign/webhooks/<token>" -H "Content-Type: application/json" \
     -H "X-ZS-WEBHOOK-SIGNATURE: $SIG" -d "$BODY"
# X18 unsigned: drop the X-ZS-WEBHOOK-SIGNATURE header          -> 401
# X19 wrong signature on the shared address: SECRET=wrong, URL https://<host>/documents/signature_progress -> 401
# X20 another company: Bodhi's token and SECRET, Arka's request id -> 200, Arka's document unchanged
# X21 unknown address: https://<host>/zoho_sign/webhooks/nope    -> 404
# E32 unknown request: request_id 999                            -> 200, nothing changes
# X22 staging without a platform secret: unsigned body to /documents/signature_progress -> 401
#     (or in a staging console: ZohoEsignHelper.verify_signature("{}", nil, nil) # => false)
# E34 development only, ZOHO_WEBHOOK_SECRET blank: unsigned body to http://localhost:3000/documents/signature_progress -> 200
```

**Requests the page doesn't offer (E4, X1, X2, E23, E24, X16).** Logged in as the user under test,
in the browser's developer console on any CapHive page:

```js
const csrf = document.querySelector("meta[name=csrf-token]")?.content || "";
// E4 / X1 / X2: connect (POST), reconnect (PATCH) or disconnect (DELETE) - expect 422 or a redirect, nothing saved
fetch("/entities/<entity id>/zoho_sign_connection", { method: "POST", redirect: "manual",
  headers: { "X-CSRF-Token": csrf, "Accept": "text/vnd.turbo-stream.html" },
  body: new URLSearchParams({ "zoho_sign_connection[region]": "xx", "zoho_sign_connection[client_id]": "1000.X",
                              "zoho_sign_connection[client_secret]": "x", "zoho_sign_connection[grant_code]": "x" }) })
  .then(r => r.status);
// E23 / E24 / X16: extend to a past date, today or "not-a-real-date", then reload the document page
fetch("/documents/<document id>/extend_esign_expiry", { method: "PATCH", redirect: "manual",
  headers: { "X-CSRF-Token": csrf }, body: new URLSearchParams({ expire_by: "2020-01-01" }) });
```

**Logs (E8).** After a connect, the request log shows `client_secret` and `grant_code` as `[FILTERED]`:
`grep -n "zoho_sign_connection" log/<env>.log | tail`.

**Cutover (E10).** In a console: `ZohoSignAccount.for_document(Document.find(<id>)).platform?` is
`false` for a document whose `sent_for_esign_date` equals the connection's `connected_at`.

**Daily check (X8 and others).** `DocumentEsignUpdateJob.perform_now(nil, nil)`.

**Simulated Zoho failures (X9, X10, X13, X15, X23, X26).** In a console — only that console
process is affected; run the job there with `perform_now`:

```ruby
# X9 timeout / X10 rate limit during a status check -> document unchanged, job scheduled for retry (Sidekiq)
ZohoSignClient.prepend(Module.new { def get_request(*) = raise(ZohoSignClient::TransientError, "simulated timeout") })
EsignUpdateJob.perform_now(<document id>, nil)          # X10: raise ZohoSignClient::RateLimited instead

# X13 timeout while sending -> document Failed, can be resent
ZohoSignClient.prepend(Module.new { def create_request(**) = raise(ZohoSignClient::TransientError, "simulated timeout") })
EsignJob.perform_now(<document id>, <user id>)

# X15 submit refused after create -> document Failed, no draft left in Zoho
ZohoSignClient.prepend(Module.new { def submit_request(*) = raise(ZohoSignClient::RequestError, "simulated refusal") })
EsignJob.perform_now(<document id>, <user id>)

# X23 unknown status -> statuses unchanged, response in the document's eSign log
ZohoSignClient.prepend(Module.new { def get_request(id) = super.tap { |json| json["requests"]["request_status"] = "paused" } })
EsignUpdateJob.perform_now(<document id>, nil)

# X26 certificate unavailable at completion (all signers signed in Zoho) -> Completed, signed copy, no certificate
ZohoSignClient.prepend(Module.new { def completion_certificate(*) = raise(ZohoSignClient::TransientError, "simulated 500") })
EsignUpdateJob.perform_now(<document id>, nil)
```

## Troubleshooting

| Symptom | Likely cause | What to do |
|---|---|---|
| Send refused with "…uses Aadhaar eSign…" or "…uses e-stamping…" | The company moved from Digio and the document or its template still has these settings | See [Aadhaar and e-stamping](#aadhaar-and-e-stamping) |
| Panel shows **Needs reconnect**; company admins and support got the reconnect email; sends refused with "…Zoho account needs to be reconnected…" | The client deleted or reset the Self Client, or revoked the refresh token | The client generates a new grant code and support uses **Reconnect** (blank Client Secret keeps the stored one). The cutover date is kept |
| Statuses only change after **Get eSignatures' updates** / the daily check | Webhook missing, wrong secret, or disabled by Zoho | Check "Last update" on the panel. Zoho **disables a webhook after 20 consecutive failures** — re-enable it in Zoho. If the secret is wrong: **Regenerate webhook secret**, paste the new one into the Zoho webhook, **Test Url** |
| Every Zoho update to the shared address is refused (401) in staging/production | `ZOHO_WEBHOOK_SECRET` missing, or HMAC/secret on CapHive's Zoho webhook differs | Set the secret in credentials and the same one on the Zoho webhook |
| Status checks retried, "rate limited" in logs | Zoho allows about 50 API calls per minute per account | Nothing to do; jobs retry with back-off (5 attempts, then an error report) |
| Send fails with "Error sending <name> for eSigning - …" | The reason after the dash is Zoho's or the network's | Fix the cause (file, signers, Zoho status) and use **Re-Send for eSignatures** |
| Error report with source "ZohoSignClient platform" ("Zoho rejected the …") | CapHive's platform refresh token revoked | Generate a new platform refresh token (above) and update credentials |

The document's eSign log (`EsignLog`) keeps every Zoho response for a document (send, status
checks, webhooks) — start there for a single document's history.
