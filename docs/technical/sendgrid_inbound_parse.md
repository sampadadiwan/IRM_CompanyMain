# SendGrid Inbound Parse Configuration

Where inbound email routing is configured on SendGrid's side, and what's set up there today.
This is dashboard/DNS state, not code — nothing here is provisioned via Pulumi or checked into
the app config, so it has to be tracked manually.

## Where to find it

**SendGrid dashboard → Settings → Inbound Parse** (`app.sendgrid.com/settings/parse`).
Login: `support@caphive.com` (same mailbox outgoing app email is sent from).

## Current configuration (as of 2026-08-25)

All three hosts route to the same Rails endpoint, `IncomingEmailsController#sendgrid`
(`POST /incoming_emails/sendgrid`), which branches on the `to` address — see
`app/packs/misc/incoming_emails/controllers/incoming_emails_controller.rb`.

| Host | Destination URL | Notes |
|---|---|---|
| `local.caphive.app` | `https://<subdomain>.ngrok-free.app/incoming_emails/sendgrid` | ngrok tunnel — subdomain rotates each time a dev restarts ngrok, so the URL needs updating in SendGrid whenever that happens |
| `dev.caphive.app` | `https://dev.altconnects.com/incoming_emails/sendgrid` | dev environment is actually served under the `altconnects.com` domain, not `caphive.app` |
| `prod.caphive.app` | `https://app.caphive.com/incoming_emails/sendgrid` | production; `INCOMING_EMAIL_DOMAIN` env var |

All three have **Spam Check** on and **Send Raw** off (parsed multipart fields, not raw MIME —
matches what the controller reads: `params[:from]`, `params[:to]`, `params[:html]`/`params[:text]`,
`params[:headers]`, `params[:attachments]`).

## Not yet configured: `updates.caphive.com`

The Deal Update Agent domain (`DEAL_INGEST_DOMAIN`, see
`app/packs/startups/deals/models/deal_ingest_address.rb` and
`docs/product/deals/deal_update_agent/technical_design.md`) is **not** in the Inbound Parse list
above. The app-side webhook branching and `DealIngestAuthenticator` already exist and are ready
to receive mail — this domain just hasn't been added on the SendGrid/DNS side yet.

To finish it:
1. DNS: add an MX record — `updates.caphive.com MX 10 mx.sendgrid.net`
2. SendGrid → Inbound Parse → **Add Host & URL** — host `updates.caphive.com`, destination
   `https://app.caphive.com/incoming_emails/sendgrid`, Send Raw unchecked.

## Troubleshooting

If an inbound email (an `IncomingEmail` or a deal-ingest email) never shows up, check this table
before assuming an app bug — a stale ngrok URL, or a domain not yet added in SendGrid, is a more
common cause than a code defect.
