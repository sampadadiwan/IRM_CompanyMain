# E4 — Subprocessor List

**Checklist row:** E4 · **Done when:** published and dated
**Status:** **DRAFTED — do not publish until §5 is resolved.** Every entry below is derived from code, configuration or infrastructure actually present in the repository, with the proving file cited. Three entries (§2) require a business decision before publication because they are not currently disclosed anywhere.

**Data basis:** repository sweep 2026-08-16. `privacy.html` §5 currently contains six placeholder rows (`[Sub-processor name]`) and — critically — **no category for AI/LLM providers at all**, which for CapHive is the most sensitive category. This document supplies the real list.

> **Publication note.** A subprocessor list is a standing commitment: once published you owe customers notice before adding to it. Agree the notice period (§5) before the page goes live. `privacy.html:189` currently has `[notice period]` unfilled.

---

## 1. Core subprocessors — publish these

### Infrastructure

| Subprocessor | Legal entity | Service | Data processed | Location | Evidence |
|---|---|---|---|---|---|
| **Amazon Web Services** | Amazon Web Services, Inc. | All compute, storage, networking, load balancing, DNS, certificates | **All customer data.** Fund records, LP records, documents, backups | `ap-south-1` (Mumbai), `ap-south-2` (Hyderabad), `us-east-1` (N. Virginia) | `IRM-Infra/compute.py`, `network.py`, `alb.py`; `Pulumi.production-*.yaml` |
| **Amazon S3** | Amazon Web Services, Inc. | Document storage + database backups | Subscription documents, KYC identity documents, fund reports, full DB backups | Same as above, replicated cross-region | `config/storage.yml:58-63`; `config/initializers/shrine.rb:11-22`; `lib/tasks/aws.rake` |
| **Amazon SES** | Amazon Web Services, Inc. | Outbound transactional email | Recipient name + email, and message content: capital call notices, distribution notices, investor statements, invitations, password resets | `ap-south-1` / `us-east-1` | `config/application.rb:98-106`; `.env.production.in:30` |
| **Amazon SNS** | Amazon Web Services, Inc. | Email bounce/complaint notifications | Recipient email addresses | Same | `Gemfile:78`; `app/packs/core/email_deliverability/controllers/ses_notifications_controller.rb` |

### Document execution and identity

| Subprocessor | Legal entity | Service | Data processed | Location | Evidence |
|---|---|---|---|---|---|
| **Digio** | Digio (Product Fintech Solutions Pvt. Ltd.) | **Default** e-signature provider; also KYC verification | Documents sent for signature; signer name, email, phone; identity verification data | India | `app/.../digio_esign_helper.rb:19`; `kyc_verify.rb:7,119`; `.env.production.in:16` = `https://api.digio.in`; `docs/technical/esigning.md:3` |
| **DocuSign** | DocuSign, Inc. | Alternative e-signature provider, selected per tenant | Documents sent for signature; signer name and email | US / per DocuSign region | `app/.../docusign_esign_helper.rb:9-13`; `Gemfile:4`; provider switch `esign_helper.rb:6` |
| **IDfy** | IDfy (Baldwin Technologies Pvt. Ltd.) | AML / sanctions screening | Investor identity data submitted for screening; screening results | India | `app/.../aml_api_response_service.rb:44-45,56-57` (`https://eve.idfy.com`) |

### Messaging

| Subprocessor | Legal entity | Service | Data processed | Location | Evidence |
|---|---|---|---|---|---|
| **WATI** | Clare.AI / WATI (WhatsApp Business API provider) | WhatsApp notifications, **2FA one-time codes**, AI support chat, operational alerts | Phone numbers, notification message bodies, OTP codes, chat conversations, document links | Per WATI | `app/.../whatsapp_general_notification.rb:8-12,57-186`; `grafana_alerts_controller.rb:3`; `whatsapp_chat_dispatcher.rb` |
| **Twilio** | Twilio Inc. (Verify API) | SMS one-time passcodes | Phone number in E.164. **Twilio mints and holds the code — CapHive never receives it** | US / per Twilio | `app/.../twilio_sms_delivery.rb:1-30,142-150`; `Gemfile:147` |
| **SendGrid** | Twilio SendGrid | **Inbound** email parsing only (email filing into the platform). Outbound is SES, not SendGrid | Full inbound message bodies, attachments, sender addresses | US | `app/.../incoming_emails_controller.rb:3-11`; `config/routes.rb:159`; `Gemfile:267` |

### AI / LLM providers — **the most sensitive category, and the one currently undisclosed**

Prompts sent to these services can contain fund data, portfolio company data, KPI values, document contents and investor information. `privacy.html`'s placeholder taxonomy has no category for this at all.

| Subprocessor | Legal entity | Service | Data processed | Location | Evidence |
|---|---|---|---|---|---|
| **OpenAI** | OpenAI, L.L.C. | LLM inference: document Q&A, KPI extraction, remittance reconciliation, letter generation, portfolio reports | Prompt contents — fund, portfolio, KPI and document data | US | `config/initializers/open_ai.rb:1-4`; `app/packs/ai/llm_initializer.rb:19`; `doc_llm_base.rb:42`; `kpi_xl_extraction_engine.rb:25`; `remittance_reconciler.rb:13` |
| **Anthropic** | Anthropic, PBC | LLM inference (Claude) | Same class of prompt data | US | `app/packs/ai/llm_initializer.rb:25`; `ai_assistant.rb:22`; `doc_llm_base.rb:47`; `llm_service.rb:51` |
| **Google** | Google LLC (Gemini API) | LLM inference; folder and report summarisation | Same class of prompt data | US | `config/initializers/ruby_llm.rb:3`; `llm_initializer.rb:33`; `llm_report_job.rb:13` |
| **OpenRouter** | OpenRouter, Inc. | LLM request routing | Same class of prompt data. **Routes onward to further model providers — disclose as a fourth-party exposure** | US | `app/packs/ai/llm_service.rb:52`; `llm_models.rb` |
| **SerpAPI** | SerpApi, LLC | Web search for AI agents | Search query text leaves the platform | US | `lib/agent_tools/web_search_tool.rb:24-35`; `Gemfile:276` |

> **TODO-VERIFY, and a prospect will ask this first:** confirm whether zero-data-retention / no-training terms are in place with OpenAI, Anthropic, Google and OpenRouter. Default consumer API terms differ from enterprise terms on retention. **If the answer is "default terms", say so** — do not let the list imply an agreement that has not been signed. A fund CFO's first question about LLM usage is always "does our LP data train your model."

### Productivity integrations (customer-initiated)

| Subprocessor | Legal entity | Service | Data processed | Evidence |
|---|---|---|---|---|
| **Google (Workspace / Apps Script)** | Google LLC | Gmail add-on — files email into CapHive from a user's mailbox | Email content the user chooses to file | `config/gmail_addins.yml`; `gmail_addin_controller.rb`; `addons/gmail/` |
| **Microsoft (365 / Outlook)** | Microsoft Corporation | Outlook add-in — same data path | Email content the user chooses to file | `config/outlook_addins.yml`; `lib/templates/outlook_manifest.xml.erb` |

> **Status caveat:** the Gmail add-on has been validated on staging; the Outlook add-in has never been sideloaded. Do not describe both as "tested" without saying which.

### Development and operations (no customer data in normal operation)

| Subprocessor | Legal entity | Service | Note | Evidence |
|---|---|---|---|---|
| **GitHub** | GitHub, Inc. (Microsoft) | Source hosting; app servers clone at deploy; CI | Source code, not customer data | `config/deploy.rb:14`; `.github/workflows/infra-checks.yml` |
| **Pulumi** | Pulumi Corporation | Infrastructure state | Resource IDs, IPs, ARNs, some secret material. **Currently under a personal login** — `IRM-Infra/PULUMI_STATE.md:3-11` flags migration to an S3 backend as pending, and `DR_GUIDE.md §10` records it as a DR dependency | `IRM-Infra/PULUMI_STATE.md` |
| **Docker, Inc.** | Docker, Inc. | Container images at build/boot (`elasticsearch:8.19.0`, `redis-stack-server`, `xirr_py`) | No customer data | `db_redis_es.ami.pkr.hcl:171-172`; `config/deploy.rb:337-338` |

---

## 2. Three entries that need a decision before publication

### 2.1 Google Analytics 4 — in the **authenticated application**

`app/packs/core/base/views/layouts/modernize.html.erb:58` loads GA4 (`G-4CPQNX69HM`) on every authenticated page, via the global layout. Google therefore receives page URLs, IP and device data for signed-in fund staff and LPs.

### 2.2 Microsoft Clarity — **session recording** in the authenticated application

`modernize.html.erb:171-186` loads Microsoft Clarity, live in production (`.env.production.in:48` = `CLARITY_CODE=tdkfg7xas0`). It records sessions and heatmaps, and at lines 183-185 tags each session with `entity_id`, **the client fund's name** (`current_user.entity.name`), and the user's role.

**Microsoft receives session recordings of fund administration screens, tagged with the client's name.** Neither this nor GA4 appears in any current disclosure, and `cookies.html:149` affirmatively states the opposite. See [`E_SECURITY_CLAIMS_AUDIT.md`](E_SECURITY_CLAIMS_AUDIT.md) §2.

**Recommendation: remove both from the authenticated app** rather than disclose them. Session recording over LP capital account screens is a hard conversation with a fund CFO and the analytics value does not repay it. Marketing-site analytics (the B-group work) is a separate and legitimate context.

### 2.3 QuickChart.io

`app/packs/ai/ai_portfolio_reports/views/ai_portfolio_reports/export_docx.html.erb` and `export_pdf.html.erb` embed chart images rendered by `quickchart.io` — **the chart data values travel in the URL to a third party**. For a portfolio report that is portfolio company performance data.

**Recommendation: render charts server-side** and drop this subprocessor. It is a small change that removes a data-egress path that would otherwise need explaining in every diligence conversation.

---

## 3. Frontend CDNs

Loaded by the authenticated app layout. These receive each user's IP, User-Agent and Referer on every page load, which makes them subprocessors in the GDPR sense even though no application data is sent:

`cdnjs.cloudflare.com` · `code.jquery.com` · `cdn.datatables.net` · `cdn.jsdelivr.net` · `unpkg.com` · `cdn.sheetjs.com` · `vjs.zencdn.net` · `releases.transloadit.com` · `fonts.googleapis.com` / `fonts.gstatic.com`

Evidence: `modernize.html.erb:32,38-52,69-75,79,92-95`; `application.html.erb:53-54`.

> **Security note, not just a disclosure note:** there is **no Content-Security-Policy** (`config/initializers/content_security_policy.rb` is entirely commented out) and **no Subresource Integrity hashes** on these tags. Each CDN is a supply-chain path into the authenticated application. Self-hosting these assets, or at minimum adding SRI, both shortens this list and closes a real risk. A CTO who checks will find it.

---

## 4. Explicitly **not** subprocessors — do not list

Named because they appear in the repo and would otherwise be over-disclosed:

| Item | Why not |
|---|---|
| **New Relic** | `gem 'newrelic_rpm'` is **commented out** (`Gemfile:255`). Not active. *(But `config/newrelic.yml:15` still holds a plaintext licence key — rotate and delete.)* |
| **Sentry / Rollbar / Datadog / Bugsnag** | None present. Error reporting is email-only via `exception_notification` → SES (`Gemfile:72`; `config/initializers/exception_notification.rb:14-18`). |
| **Stripe / any payment processor** | None. The `Payment` model is a ledger record, not a gateway. |
| **Dropbox Sign / HelloSign** | A design doc exists but there is **zero code**. Not integrated. |
| **Facebook Pixel, Google Tag Manager, Brevo** | Present only in `app/packs/core/base/views/layouts/investment_solutions.html.erb`, a vendored WordPress theme demo referenced by no controller. **Delete the file** — it ships live third-party tracker IDs in the repo. |
| **Market data / pricing feeds** | None. The `eu_central_bank` gem (`Gemfile:91`) fetches ECB reference FX rates and is the only external market-data dependency. |

---

## 5. Before publishing — TODO-HUMAN

- [ ] **Resolve §2** (GA4, Clarity, QuickChart). Removal is recommended; disclosure is acceptable; silence is not.
- [ ] **Confirm zero-retention / no-training terms** with each LLM provider, and state the actual position.
- [ ] **Fill `privacy.html:189`** with a real subprocessor-change notice period. 30 days is the market norm.
- [ ] **Add the AI/LLM category** to `privacy.html` §5 — the current placeholder taxonomy omits it entirely.
- [ ] **Confirm each vendor's contracting entity and DPA status.** This list names services proven to be in use; it does **not** prove a DPA is signed with each. A subprocessor list that outruns the DPAs behind it creates the exposure it was meant to close.
- [ ] **Date the page and commit to a notice mechanism** — E4's done-when test is "current and dated".
- [ ] Give this document to counsel with the E3 DPA instructions in [`HUMAN_ACTIONS.md`](HUMAN_ACTIONS.md); the annex is drafted from exactly this table.

## 6. Published format

Publish as `subprocessors.html` on the website — its own URL, linked from `security.html` and `privacy.html` §5. Columns: **Subprocessor · Purpose · Data processed · Location**. Keep the evidence column in this internal document only; prospects need the fact, not the file path.

Head the page with the last-updated date and the notice commitment, e.g.:

> *Last updated: <date>. We will give customers at least 30 days' notice before adding a subprocessor that processes personal data.*
