# ⚠ URGENT — Published Security Claims That Cannot Be Substantiated

**Read this before anything else in this folder.**

**What this is:** the live security page at `website_src/pages/security.html` makes several claims that no evidence in the codebase or `docs/` supports, and at least two that the infrastructure code **contradicts**. The GTM plan's entire strategy for the security pack is to *volunteer* it to prospects' GCs and CTOs before they ask (`us_gtm_zero_budget_notes.md` §7, §8). **Volunteering a document containing an unsubstantiated certification claim is materially worse than having no security page at all.**

**Scope of my check:** I verified the claims below directly, twice — once via a full repo sweep, once by reading the cited files myself. I am reporting what the repository does and does not contain. **I cannot see outside the repository.** If a SOC 2 report or an ISO certificate exists in a Google Drive, with counsel, or in an auditor's portal, then the finding is "the evidence is not in the repo" rather than "the claim is false" — but somebody must confirm which, and the burden is on producing the document.

**No claim in this file is my inference. Every row cites a file and line.**

---

## 1. The four that must be resolved before the page is shown to any prospect

### 1.1 SOC 2 Type II — claimed as held. No evidence found.

| Where | What it says |
|---|---|
| `security.html:43` | Trust badge: **"SOC 2 Type II"** |
| `security.html:110` | *"Our SOC 2 Type II documentation and the control set it covers, under NDA"* |
| `security.html:197` | *"we **hold a SOC 2 Type II position** alongside it"* |

**What exists in the repo:** one line, `docs/security/security_event_review_methodology.md:3` — *"Scope: All systems that are in-scope for compliance (SOC 2)"*. That is **scoping language for an intended future audit**, not an attestation. There is no report, no auditor named, no control mapping, no bridge letter, no readiness assessment, no Type I preceding a Type II.

**Two things make this worse than a simple overstatement:**

1. **The GTM plan itself says SOC 2 does not exist yet.** `us_gtm_prerequisites.md` §6 states *"SOC 2 Type I is deliberately not in this table"* and *"fund it from the first closes"*; `us_gtm_zero_budget_notes.md` §10 budgets *"SOC 2 Type I — ~$5–15K"* as a future one-time cost. **The founders' own planning documents describe SOC 2 Type I as unstarted while the website advertises Type II as held.** Type II additionally requires an observation period of typically 3–12 months *after* Type I. These two positions cannot both be true.
2. **A hedge was removed.** The HTML comment at `security.html:96-99` records that an earlier *"audit in progress, targeting December 2026"* line was deleted. The page moved from a qualified statement to an unqualified one. That history is in git and is discoverable.

**Required action: remove the claim, or produce the report. There is no third option.** A fund's GC will ask for the report in the first email; "SOC 2 Type II" on a badge and "we're working towards it" on the call is the single fastest way to lose a deal in this market, and it is a misrepresentation risk in a contract negotiation.

### 1.2 ISO/IEC 27001:2022 — claimed as certified. No evidence found.

| Where | What it says |
|---|---|
| `security.html:45` | Trust badge: **"ISO 27001:2022"** |
| `security.html:109` | *"Our ISO/IEC 27001:2022 certificate and the scope statement behind it"* |
| `security.html:197` | *"Our information security management system **is certified** against ISO/IEC 27001:2022"* |

**What exists in the repo:** nothing. No certificate, no Statement of Applicability, no scope statement, no certification body, no ISMS documentation, no internal audit records, no management review minutes. The only ISO mentions anywhere in `docs/` are in marketing documents.

*"Is certified"* is an unqualified affirmative representation about a third-party audited status. **Same required action as SOC 2.**

### 1.3 "TLS 1.3 in transit" — contradicted by the infrastructure code

`security.html:44` badge: **"AES-256 at rest · TLS 1.3 in transit"**

TLS terminates at the AWS Application Load Balancer. The listener is created at `IRM-Infra/alb.py:53-58` **with no `ssl_policy` argument** — I read the file and confirmed it. AWS therefore applies its default policy, `ELBSecurityPolicy-2016-08`, which negotiates **down to TLS 1.0**.

So the published claim is not merely unproven — the deployed configuration permits the opposite. A prospect's CTO running any TLS scanner against `caphive.com` will see this in under a minute, and it is the kind of finding that reframes every other claim on the page as unreliable.

**Fix is one line of IaC**, after which "TLS 1.2+" becomes true:
```python
ssl_policy="ELBSecurityPolicy-TLS13-1-2-2021-06",
```
Pin it, redeploy, verify with `sslyze` or SSL Labs, *then* say "TLS 1.2+ (TLS 1.3 preferred)".

### 1.4 "AES-256 at rest" — true for backups and files, not demonstrable for the database

- **True and citable:** S3 buckets carry SSE-S3 AES256 (`lib/tasks/aws.rake:790-807`), covering uploaded documents and all database backups.
- **Not demonstrable:** **no EBS volume in the IaC sets `encrypted`.** I read all four declarations — `IRM-Infra/compute.py:228-232` (web), `:293` (DB primary), `:312` (DB replica), `:346` (observability). Each specifies only `device_name`, `volume_size`, `volume_type: gp3`.

MySQL runs on EC2 with its data on those EBS volumes, so **the volume holding all customer data is not encrypted by anything in the codebase.** It may still be encrypted in fact — if the source AMI snapshots are encrypted, or if EBS-encryption-by-default is enabled on the account. Neither is visible in the repo.

**This is the highest-value item to check, because it is the one a fund CTO's questionnaire asks in exactly these words.** Verify in the AWS console (EC2 → Volumes → Encryption column) for both production accounts. Then either fix the IaC or stop claiming it.

---

## 2. The cookie policy contradicts the application

**This is the highest-liability item on the site**, because it is a written privacy representation that the product falsifies on every page load.

`website_src/pages/cookies.html:149` states:

> *"The platform application is separate. app.caphive.com … uses only the cookies strictly necessary to authenticate you and keep you signed in, together with a token that protects requests against cross-site request forgery. **It does not run analytics or marketing cookies.** [To be verified before launch.]"*

**The authenticated application runs two analytics services.** The global layout — `app/packs/core/base/views/layouts/modernize.html.erb`, applied to every authenticated page via `application_controller.rb:2` — loads:

| Line | What |
|---|---|
| `:58` | **Google Analytics 4**, `G-4CPQNX69HM`, unconditionally |
| `:173-176` | **Microsoft Clarity** — session recording and heatmaps |
| `:183-185` | Passes to Clarity: `entity_id`, **`current_user.entity.name`** (the client fund's name), and `current_user.curr_role` |

Clarity is live in production: `.env.production.in:48` = `CLARITY_CODE=tdkfg7xas0` (staging: `bfdvhyabfe`). I confirmed both.

**What this means in plain terms:** Microsoft receives session recordings of fund administration screens — capital calls, LP records, allocations — tagged with the client fund's name. Neither Google nor Microsoft appears in the privacy policy or in any subprocessor list.

To the page's credit, its own TODO at `cookies.html:155-157` predicted precisely this and asked engineering to check before publishing. **That check has now been done, and the answer is that the statement is false.**

**Three options, and this needs a decision, not a rewrite:**

1. **Remove GA and Clarity from the authenticated app layout.** Cleanest. Keeps the cookie policy true, removes a subprocessor from the DPA annex, and removes the "fund name sent to Microsoft" problem entirely. Analytics on the *marketing* site (which is what the B-group work configures) is unaffected — that is a separate, legitimate, consented context.
2. **Keep them and disclose fully** — rewrite `cookies.html`, add both to the privacy policy and the subprocessor list, add a consent mechanism for the authenticated app, and **at minimum stop passing `entity.name`** to Clarity. Note this makes an LP-data session-recording disclosure part of every DPA negotiation.
3. **Make them configurable per tenant**, defaulted off, so a fund can decline.

Option 1 is the recommendation. Session recording on a screen displaying LP capital accounts is a hard conversation with a fund CFO, and the analytics value does not repay it.

---

## 3. Claims that need softening rather than removing

These are not false, but they are stated more strongly than the evidence supports.

| Claim | Where | Reality |
|---|---|---|
| **"SSO / OAuth"** badge; *"Central identity management … part of how we expect institutional teams to use the platform"* | `security.html:46`, `:216`; also `privacy.html:215` | **There is no SAML and no OIDC relying-party support.** No `omniauth`, no `ruby-saml`, no `devise_saml_authenticatable` in the Gemfile. CapHive is an OAuth2/OIDC **provider** (Doorkeeper, `config/initializers/doorkeeper.rb`) so AI clients can call *in*. A CTO reading "SSO" assumes Okta/Entra federation and will be told no on the call. **Rewrite to what is true**, which is genuinely good: TOTP/WhatsApp/SMS MFA, RBAC with 153 Pundit policies, OAuth 2.0 + OIDC provider with PKCE for API access. |
| *"Production access requires an approved reason"* | `security.html:78`, `:209` | No access-request workflow, ticketing integration, break-glass procedure or JIT tooling found. **Support access to tenant data is genuinely gated** by `support_client_mappings` (`base_scope.rb:15-23`) — cite that, it is real. **SSH/OS access is not**: `IRM-Infra/compute.py:202` opens port 22 to `0.0.0.0/0`, which also contradicts `docs/security/cybersecurity_risk_management_policy.md:16-18` ("no security group permits unrestricted (0.0.0.0/0) access to administrative ports (SSH)"). Key-only auth is enforced, but the port is world-reachable. Never answer a questionnaire "SSH restricted to bastion/VPN". |
| *"dependencies are monitored for known vulnerabilities"* | `security.html:88` | **Currently false in CI.** Commit `753216c99` (2026-07-06) deleted `.github/workflows/lint.yml`, which ran Brakeman and bundler-audit. Only `infra-checks.yml` remains, and it runs no security scanning and no tests. The gems are still installed, so the fix is cheap — restore the workflow and the claim becomes true again. Until then this also makes `cybersecurity_risk_management_policy.md:39,70` false. |
| *"access is reviewed when roles change"* | `security.html:68` | No documented user access-review procedure. The risk policy describes quarterly *security-group* review, which is a different thing. |
| *"issues triaged by severity with a target time to fix"* | `security.html:88` | SLAs exist only for **GuardDuty findings** (24h High/Critical, 5 business days Medium). No SLA for reported application vulnerabilities. |
| *"Changes are peer reviewed before release"* | `security.html:88` | Mixed and unevidenced — no branch protection or CODEOWNERS in the repo. Some commits carry PR numbers, recent ones are direct pushes to `main`. |
| *"Tenant isolation, so one client's data is not queryable from another client's context"* | `security.html:158` | **The isolation mechanism is real and well built** (see [`E1_security_page_content.md`](E1_security_page_content.md) §4). But `docs/technical/security_review_2026_07.md:22` records **H1 as an accepted risk** — *"Support role keeps cross-tenant access after switch — REQUIRED BY DESIGN"* — and the same document records an **open Critical, C1** (`eval`-based formula engine, lines 36-97) whose own text states that because all tenants share app processes, *"RCE in one tenant is a path to reading or corrupting every tenant's data."* **TODO-VERIFY: confirm C1's current remediation status before this sentence is published or answered in a questionnaire.** I did not verify whether it has been fixed since. |
| *"AI agent access scoped to the same permissions as the user who invoked it, with every agent action written to the audit trail"* | `security.html:160` | **TODO-VERIFY.** A very specific, very falsifiable claim. The MCP tool layer and `mcp_auth_service.rb` exist, but I did not confirm that every agent tool call passes through Pundit *and* writes an `audits` row. Needs a targeted code check before publishing. |

---

## 4. Two housekeeping items with security consequences

1. **A plaintext New Relic licence key sits in `config/newrelic.yml:15`**, while `gem 'newrelic_rpm'` is **commented out** at `Gemfile:255`. Dead config with a live credential. Rotate the key and delete the file.
2. **`config/deploy_id_rsa` — a plaintext OpenSSH private key — is still in the repository.** `docs/dr_review/point_03_committed_secrets.md` documents this as "Exposure A", explicitly left as-is by request, with git history not purged. Rotation status unknown. A GC reviewing SDLC practices will ask, and "it is in our public-facing repo history" is a bad answer. Also confirm `config/master.key` and `config/credentials/*.key` are gitignored and absent from history.
3. **`app/packs/core/base/views/layouts/investment_solutions.html.erb`** is a vendored WordPress theme demo containing live third-party tracker IDs (Facebook Pixel, GTM, Brevo). No controller references it. Delete it — it is dead code that would appear in any source review.

---

## 5. What is genuinely strong — lead with these instead

Removing the unsupported claims does **not** leave a weak page. The verified security posture is better than most seed-stage vendors' and considerably better than the page's own weakest sections suggest:

- **Multi-tenancy isolation that is enforced, not conventional.** `after_action :verify_authorized` and `verify_policy_scoped` are global (`with_authentication.rb:5-6`); `ApplicationPolicy` denies by default; 153 Pundit policy classes; `RecordNotFound` and `NotAuthorized` return the same response so IDOR probes cannot distinguish "not yours" from "does not exist".
- **Audit logging with before-and-after values** across 49 models including `Fund`, `CapitalCall`, `CapitalCommitment`, `AccountEntry`, `Payment` — with impersonation correctly attributed to the *support* user, not the impersonated one (`config/initializers/audited.rb:1`).
- **Backups that are actually tested.** Nightly full + 30-minute incrementals via Percona XtraBackup, 90-day retention, versioned and cross-region replicated with delete markers deliberately not replicated. **`docs/dr_drills.md` contains 15 real, logged drills with measured RTOs** and an automated post-recovery verification task. Most vendors claiming "tested restores" cannot produce this.
- **Separate AWS accounts** for production (`825199636520`) and staging (`174852986003`), with separate Pulumi state buckets and separate credentials.
- **Documented, severity-graded internal security reviews** — five of them, totalling ~2,500 lines, including one that records an accepted risk honestly rather than hiding it.
- **AWS WAFv2** with managed rule sets, **Rack::Attack** rate limiting in all environments, **MFA across three delivery channels**, bcrypt cost 12, account lockout at 6 attempts, 60-minute session expiry.

**The honest version of this page is a competitive asset.** "No SOC 2 yet, here is our roadmap and here are 15 logged DR drills with measured recovery times" is a *better* story for a technically savvy GP than an unverifiable badge — and it is exactly the "specificity" trust mechanism the GTM plan's §1 identifies.

---

## 6. Required actions, in order

| # | Action | Owner | Urgency |
|---|---|---|---|
| 1 | Produce the SOC 2 report and ISO certificate — **or remove both claims from `security.html` (lines 43, 45, 109, 110, 197)** | Founders | **Before any prospect sees the page** |
| 2 | Decide GA + Clarity in the authenticated app (§2). Recommend removal | Founders + eng | **Before `cookies.html` or `privacy.html` is published** |
| 3 | Verify EBS encryption in both prod AWS accounts; fix IaC or drop the claim | Eng | Before answering any questionnaire |
| 4 | Pin `ssl_policy` on the ALB listener; then say "TLS 1.2+" | Eng | Same |
| 5 | Confirm remediation status of C1 (`eval` RCE) and H1 (accepted cross-tenant support access) | Eng | Before publishing the tenant-isolation sentence |
| 6 | Rewrite the "SSO / OAuth" badge to what is true | Founders | With the page rewrite |
| 7 | Restore the deleted Brakeman + bundler-audit CI workflow | Eng | Cheap; makes an existing claim true again |
| 8 | Rotate the New Relic key, delete `config/newrelic.yml`, rotate `config/deploy_id_rsa`, delete the vendored WordPress layout | Eng | Housekeeping |
| 9 | Verify the AI-agent audit-trail claim (`security.html:160`) or remove it | Eng | Before publishing |

Replacement page content that carries only verified claims is in [`E1_security_page_content.md`](E1_security_page_content.md). It is written so that every line traces to a file, and the items above appear in it as explicit gaps rather than as silence.
