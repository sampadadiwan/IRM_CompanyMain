# SES Bounce/Complaint Handling — Design Plan

This is a design plan, not yet implemented. It describes how to trap AWS SES
bounce/complaint events and mark the originating `Noticed::Notification` as
bounced. See [notifications_system.md](notifications_system.md) for the
existing notification architecture this builds on.

---

## 1. Current state

- Outbound mail is sent via the **SES SMTP interface**
  (`config/application.rb:96-104`), using
  `Rails.application.credentials[:SES_SMTP_USERNAME/PASSWORD]`. The app does
  not call the SES API directly and has no `aws-sdk-ses` / `aws-sdk-sns` gem.
- `ApplicationMailer#mark_delivered` (`app/packs/core/base/mailers/application_mailer.rb:6`)
  is an `after_deliver` hook that writes delivery metadata back onto the
  `Noticed::Notification` row (`email`, `email_sent`, `subject`). This is the
  only place delivery state is currently tracked.
- `noticed_notifications` (schema) has **no bounce/complaint/status column** —
  only `email_sent` (bool) and `email` (json blob).
- The app already has a precedent for an unauthenticated inbound webhook with
  idempotent processing: `IncomingEmailsController#sendgrid`
  (`app/packs/misc/incoming_emails/controllers/incoming_emails_controller.rb:7`),
  which matches an inbound `Message-ID` header to dedupe retries. The new SES
  webhook should follow the same shape.

Bounce/complaint notifications are configured at the **SES identity level**
in AWS, independently of whether mail is sent via SMTP or the API — so
switching delivery method is not required.

---

## 2. AWS-side setup (outside this repo)

1. On the sending identity (domain or address), enable SES **event
   publishing** for `Bounce` and `Complaint` events, with:
   - either an **SNS Configuration Set** destination, or the simpler legacy
     **Identity Notifications** (Bounce/Complaint topics) — either delivers
     the same JSON shape via SNS.
2. Create (or reuse) an **SNS topic** for these events.
3. Add an **HTTPS subscription** on that topic pointing at the new Rails
   endpoint (see §3). SNS will first send a `SubscriptionConfirmation`
   message that the endpoint must confirm.
4. Enable **"include original headers"** on the notification configuration —
   this echoes back any custom header set on the outgoing message (see §4),
   which is how we correlate a bounce back to a specific
   `noticed_notifications` row.

This step needs coordination with whoever manages the AWS account/IAM for
this app; it is not something this repo's code can do on its own.

---

## 3. New webhook endpoint

Add a new controller, modeled directly on `IncomingEmailsController#sendgrid`:

- **Route**: `POST /ses_notifications` (collection route, own controller —
  not nested under an existing authenticated resource).
- **Controller**: `SesNotificationsController#create`
  - `skip_before_action :verify_authenticity_token, :authenticate_user!, :set_current_entity`
  - `skip_after_action :verify_authorized`
  - Verify the SNS message signature (see §5) before trusting the payload.
  - Handle `x-amz-sns-message-type` header:
    - `SubscriptionConfirmation` → fetch `SubscribeURL` to confirm.
    - `Notification` → parse the embedded JSON `Message` field, identify
      `notificationType` (`Bounce` or `Complaint`), and enqueue a Sidekiq job
      with the raw payload (`SesBounceProcessingJob.perform_later(raw_body)`).
  - Always `head :ok` quickly — SNS retries aggressively on non-2xx and will
    eventually disable the subscription.

Processing is pushed to a background job (mirroring the existing
`ApplicationJob`/Sidekiq pattern used throughout, e.g.
`capital_distribution_payment_notification_job.rb`) so the webhook itself
stays fast and idempotent-safe.

---

## 4. Correlating a bounce to a `Noticed::Notification`

SES's bounce JSON identifies the failure by recipient email address and
SES's own `mail.messageId` — neither maps directly to our DB id. Rather than
fuzzy-matching by recipient + timestamp, set a custom header on the outgoing
mail so SES echoes it straight back:

- In `ApplicationMailer#mark_delivered` (or `setup_defaults`), add a header
  to the `Mail::Message` before delivery:
  ```ruby
  headers["X-Notification-Id"] = @notification.id if @notification
  ```
- With "include original headers" enabled (§2.4), the bounce/complaint SNS
  payload includes `mail.headers`, an array of `{name, value}` pairs
  containing this header verbatim.
- `SesBounceProcessingJob` extracts `X-Notification-Id` from
  `mail.headers` and looks up `Noticed::Notification.find_by(id: ...)`.
  - Fallback if the header is missing (e.g. older mail or non-notification
    mail like Devise emails): match by recipient email
    (`noticed_notifications.email->>'$.email.to'`) within a short time window
    of `mail.timestamp`, best-effort only.

---

## 5. SNS signature verification

No gem currently provides this (`aws-sdk-sns` is not in the Gemfile). Two
options:

- **Add `aws-sdk-sns`** and use `Aws::SNS::MessageVerifier#authentic?` —
  minimal code, one new dependency.
- **Verify by hand** with OpenSSL against `SigningCertURL` /
  `Signature` / `SignatureVersion` fields — no new dependency, more code to
  maintain.

Recommendation: add `aws-sdk-sns` (small, well-maintained, already in the
same gem family as `aws-sdk-s3`/`aws-sdk-ec2` already in the Gemfile) rather
than hand-rolling signature verification.

---

## 6. Schema change

Add to `noticed_notifications` (migration):

| Column | Type | Purpose |
|---|---|---|
| `bounced_at` | `datetime` | Set when a `Bounce` event is processed |
| `bounce_type` | `string` | `Permanent` / `Transient` / `Undetermined` (from SES payload) |
| `complained_at` | `datetime` | Set when a `Complaint` event is processed |

Kept as plain columns (matching existing `email_sent`/`read_at`/`seen_at`
style) rather than a single enum, since bounce and complaint are independent
events that can both occur over a notification's lifetime.

`Noticed::Notification` already has `NotificationExtensions`
(`config/initializers/noticed.rb`) — add a `bounced?` / `complained?` helper
there alongside the existing `email_enabled` logic.

---

## 7. Idempotency

SNS can redeliver the same notification. Use the SES payload's
`mail.messageId` (the SES-internal id, present on every bounce/complaint
regardless of header echoing) as a dedupe key — e.g. a unique index on a new
`ses_message_id` column, or a short-lived cache key — before updating
`bounced_at`/`complained_at`, so retries are no-ops.

---

## 8. Open questions for follow-up

- Should a hard bounce (`Permanent`) also flip something on `User` or
  `InvestorAccess` (e.g. `email_enabled = false`) to stop retrying a dead
  address, or is per-notification tracking sufficient for now?
- Do we want bounce/complaint surfaced in the notification dashboards
  (`app/packs/funds/dashboards/notification_dashboard.rb`,
  `admin/notifications_controller.rb`) as a filter/column? Likely yes, but
  out of scope for the initial webhook + schema work.
- Devise emails (password reset, etc.) go through `DeviseMailer`, not
  `ApplicationMailer` — they won't have a `Noticed::Notification` to
  correlate to. Decide whether bounce tracking should cover those too (would
  need a separate correlation strategy, e.g. tagging by `User#id`).

---

## 9. Alternative: poll the SES suppression list (no webhook/SNS)

A much lighter-weight option than §2–§5 above: instead of receiving push
events via SNS, periodically **pull** bounce data from AWS using a scheduled
job.

### How it works

- SES maintains an **account-level suppression list**: any address that
  hard-bounces (and, if configured, any address that complains) is
  automatically added to it. This is a one-time setting in the SES console
  (Account dashboard → Suppression list settings) — no Configuration Set,
  SNS topic, or inbound endpoint required.
- Add the `aws-sdk-sesv2` gem and a Sidekiq job (scheduled via the
  already-present `sidekiq-cron`) that calls:
  - `ListSuppressedDestinations` (paginated, supports a `start_date` filter)
    to get addresses suppressed since the last run.
  - `GetSuppressedDestination` per address for the reason
    (`BOUNCE`/`COMPLAINT`) and `LastUpdateTime`.
- For each suppressed address, find the matching `Noticed::Notification`
  row(s) — e.g. the most recent un-flagged notification sent to that
  recipient email before `LastUpdateTime` — and set `bounced_at` /
  `bounce_type` (same schema as §6) on it.

### Trade-offs vs. the SNS webhook approach

| | Webhook (§2–§5) | Suppression-list polling (this section) |
|---|---|---|
| New inbound endpoint | Yes (`SesNotificationsController`) | No |
| Signature verification needed | Yes | No |
| AWS-side setup | SNS topic + subscription + event publishing config | One checkbox (enable suppression list) |
| Latency | Near real-time | Delayed by poll interval |
| Granularity | Per-send (via `X-Notification-Id` header) | Per-address only — correlation to a specific notification is a best-effort recency match |
| New gem | `aws-sdk-sns` | `aws-sdk-sesv2` |
| Soft (transient) bounces | Captured | Not captured — suppression list only tracks hard bounces/complaints, not transient failures |

### When this is good enough

If the goal is mainly "stop treating this address as good" / "flag the
investor's email as bad" rather than "tell me precisely which send failed
and why," this is the simpler path — it reuses existing scheduled-job infra,
needs no new public endpoint, and avoids SNS signature verification
entirely. The main gap is transient bounces (e.g. mailbox full), which never
show up in the suppression list — only permanent hard bounces and
complaints do.
