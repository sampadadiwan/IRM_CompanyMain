# E1 — Security Page Content (Verified Claims Only)

**Checklist row:** E1 · **Done when:** published and linkable
**Status:** **DRAFTED.** Replacement content for `website_src/pages/security.html`.

**Read [`E_SECURITY_CLAIMS_AUDIT.md`](E_SECURITY_CLAIMS_AUDIT.md) first.** The page currently live claims SOC 2 Type II and ISO 27001:2022 certification, neither of which has any supporting evidence in the repository, plus "TLS 1.3" which the ALB configuration contradicts. This document is the replacement, not an addition.

**Rule applied throughout:** every sentence below traces to a file I read. Anything I could not verify appears as an explicit `TODO-VERIFY` and is **not** in the customer-facing prose. The prose is written to be pasted; the bracketed notes are for whoever assembles the page and must be removed before publishing.

---

## Why the honest version is the stronger version

The GTM plan's §1 names four trust mechanisms; the second is **specificity** — *"content that could only come from someone who knows fund ops deeply."* The same logic applies to security. For a technically savvy GP evaluating a vendor with no SOC 2, this:

> *"We do not have SOC 2 yet. Here is our recovery objective, here is the log of the fifteen disaster-recovery drills we ran in July with measured restore times, and here is what failed in twelve of them."*

is a **better** trust signal than an unverifiable badge — because it is checkable, and because almost no vendor at this stage can produce it. Specificity is the asset. Certification is the thing you buy later with the money from the first closes.

---

## 1. Hero

> ## Security and trust
>
> CapHive holds fund records, investor data and the documents that move money. This page sets out how that data is protected, what we can evidence today, and what we are still building. We would rather you find the gaps here than in a questionnaire.

**Trust strip — replace the current four badges with these four:**

| Badge | Why it is safe to publish |
|---|---|
| **Tenant isolation enforced in code** | 153 Pundit policies; deny-by-default; `verify_authorized` + `verify_policy_scoped` are global after-actions |
| **Full audit trail with before/after values** | `audited` gem, 49 models, `audited_changes` column |
| **Tested restores — drills logged with measured times** | `docs/dr_drills.md`, 15 drills, RTO measured |
| **Multi-factor authentication** | TOTP + WhatsApp + SMS, `devise-two-factor` |

**Do not publish:** "SOC 2 Type II", "ISO 27001:2022", "TLS 1.3", "SSO".

---

## 2. Hosting and infrastructure

> CapHive runs on Amazon Web Services. Production and staging are in **separate AWS accounts**, each with its own network boundary, its own credentials and its own infrastructure state — so a staging change cannot reach production data.
>
> We operate in three regions and agree yours at implementation: **Mumbai (ap-south-1)**, **Hyderabad (ap-south-2)** and **North Virginia (us-east-1)**. US clients are served from us-east-1, and their data stays there.
>
> Infrastructure is defined as code (Pulumi) and machine images are built from versioned templates (Packer), so environments are reproducible rather than hand-configured. Application servers sit in private subnets behind an Application Load Balancer; the database is not reachable from the internet.
>
> An **AWS WAF** sits in front of the application with managed rule sets for common web attacks, SQL injection, known-bad inputs and IP-reputation blocking. Application-level rate limiting runs in every environment.

*Evidence: `IRM-Infra/Pulumi.production-*.yaml`; `compute.py`; `network.py`; `alb.py`; `infra/waf/ap-south-1/CapHive.web_acl.json`; `config/initializers/rack_attack.rb:16-29`; account IDs in `docs/security/cybersecurity_risk_management_policy.md:15`.*

**Deliberately omitted:** any claim that the database is "managed" — MySQL, Redis and Elasticsearch are self-hosted on EC2, not RDS/ElastiCache/OpenSearch. Do not imply otherwise; a CTO who asks "which RDS engine" must get a straight answer.

---

## 3. Encryption

> **In transit.** All traffic to CapHive is encrypted. TLS terminates at the load balancer, the application refuses non-HTTPS requests, and HTTP Strict Transport Security is set. Session cookies are `secure` and `httpOnly`. Outbound mail uses STARTTLS.
>
> **At rest.** Documents and database backups are stored in Amazon S3 with **AES-256** server-side encryption, versioning, and cross-region replication. Application secrets are held in encrypted credential files with per-environment keys; infrastructure secrets are in AWS Systems Manager Parameter Store as KMS-encrypted SecureStrings. Passwords are hashed with bcrypt at cost factor 12.

*Evidence: `config/environments/production.rb:28,31`; `config/deploy/templates/nginx_conf.erb:102`; `config/initializers/session_store.rb:6-7`; `config/application.rb:105`; `lib/tasks/aws.rake:588-592,790-807`; `IRM-Infra/compute.py:169-181`; `config/initializers/devise.rb:128`.*

**Blocked pending verification — do not publish either of these until resolved:**

- 🔴 **TODO-VERIFY (database volume encryption).** No EBS volume in `IRM-Infra/compute.py` (lines 228-232, 293, 312, 346) sets `encrypted`. MySQL data lives on those volumes. Check the AWS console for both production accounts. **Until confirmed, the words "all customer data is encrypted at rest" must not appear.** Say what is true — S3 and backups — and nothing more.
- 🔴 **TODO-VERIFY (TLS version).** `IRM-Infra/alb.py:53-58` sets no `ssl_policy`, so the AWS default permits TLS 1.0. Pin `ELBSecurityPolicy-TLS13-1-2-2021-06`, redeploy, verify, **then** the sentence "TLS 1.2 or higher" may be added above.

**Also not claimed:** field-level encryption of PII. `ActiveRecord::Encryption` is configured but encrypts exactly one column — `otp_secret`, required by `devise-two-factor` (`config/application.rb:148`). The only other `encrypts` in the codebase is commented out (`note.rb:5`). Bank details, tax identifiers and KYC fields are **not** column-encrypted. Do not say they are.

---

## 4. Access control and tenant isolation

This is the strongest section and should be led with. It is also the question a fund's CTO actually cares about.

> **Tenant isolation.** Every client is a separate tenant, resolved from the request. Authorization is enforced globally rather than per-controller: every action must declare a policy and every listing must apply a tenant scope, or the request fails. The base policy **denies by default** — an action with no explicit permission is refused, not allowed. Records outside your tenant return "not found" rather than "not permitted", so probing cannot even confirm that another tenant's record exists.
>
> **Roles and permissions.** Role-based access control down to record type, with granular per-permission flags on top. 153 distinct authorization policies are enforced across the platform.
>
> **Support access is explicit and revocable.** Our support staff cannot see your data by default. Access requires a named mapping between a specific support user and your entity, which you enable and can withdraw. When support acts, the audit trail records the support user — not the client user they were assisting.
>
> **Authentication.** Passwords are bcrypt-hashed (cost 12), minimum 8 characters. Accounts lock after 6 failed attempts. Sessions expire after 60 minutes. Password reset links expire after 6 hours.
>
> **Multi-factor authentication** is available to every user, with three second factors: an authenticator app (TOTP, RFC 6238), WhatsApp, or SMS. Eight single-use backup codes are issued, stored hashed.
>
> **API access** uses OAuth 2.0 with OpenID Connect, authorization-code flow with PKCE required and HTTPS-only redirect URIs.

*Evidence: `with_authentication.rb:5-6,16-18,70-80,104-131`; `application_policy.rb:13-39,68-71`; `base_scope.rb:7-23`; `config/initializers/devise.rb:128,141,155,171,185,188,201`; `session_store.rb:5`; `user.rb:123-125`; `docs/technical/two_factor_authentication.md`; `config/initializers/doorkeeper.rb:29-34,398-400`.*

**Must be stated honestly, not omitted:**

- **MFA is available and opt-in, not enforced.** `two_factor_enabled` defaults to `false` (`db/schema.rb:4023`) and there is no org-wide enforcement setting. Write *"available to every user"* — never *"required"*. If a prospect asks for mandatory MFA, that is a roadmap conversation.
- **There is no SSO.** No SAML, no OIDC relying party. CapHive is an OAuth/OIDC *provider*. **Remove the "SSO" badge and the `privacy.html:215` SSO claim.** Suggested honest line: *"Federated SSO (SAML / Okta / Entra ID) is not supported today. If it is a requirement for your firm, tell us — it is the most-requested item on our security roadmap."* That answer loses nothing and buys credibility.
- **Password complexity rules do not exist** beyond the 8-character minimum. No rotation, no history, no expiry. Do not imply otherwise.
- **API tokens and OAuth tokens bypass 2FA by design** (`docs/technical/two_factor_authentication.md:24-25`). Disclose it in the questionnaire; it is a normal design, but discovering it unprompted looks like concealment.

🔴 **TODO-VERIFY before publishing the tenant-isolation paragraph.** `docs/technical/security_review_2026_07.md` records **H1** (line 22) as an accepted risk — support role retains cross-tenant access after switching — and an **open Critical C1** (lines 36-97), an `eval`-based formula engine whose own write-up states that with shared app processes, RCE in one tenant reaches every tenant's data. Confirm C1's current status. If it is still open, the isolation paragraph is not publishable as written.

---

## 5. Backup, retention and recovery

The single most credible section, because it can be evidenced.

> Backups are continuous rather than nightly: a **full backup every night at 23:00** and **incremental backups every 30 minutes** through the day, taken with Percona XtraBackup and streamed directly to encrypted S3 storage. The database host holds no backup credentials — it authenticates through an instance role.
>
> Backups are retained for **90 days**, versioned, and replicated to a second AWS region. Delete markers are deliberately *not* replicated, so a deletion in the primary region cannot propagate to the replica. An automated job alerts us if a backup is missing or stale.
>
> **Recovery objectives.** Recovery point objective **30 minutes**, set by the incremental cadence. Recovery time objective approximately **10 minutes** for a staging-sized dataset, scaling with database size.
>
> **We test restores rather than assuming them.** Recovery drills are run against real backups and logged with measured times, and every recovery ends with an automated verification step that proves the application is serving, the database and search index are reachable, replication is flowing and backups are armed. Our most recent successful drill completed in **8.7 minutes**. We are glad to walk your team through the drill log.

*Evidence: `db_redis_es.ami.pkr.hcl:309`; `lib/tasks/db_backup_xtra.sh`; `lib/tasks/aws.rake:588-592,781-783,790-807`; `docs/dr_review/point_06_s3_replication_codified.md:25`; `docs/dr_review/point_08_backup_retention_lifecycle.md:14-18`; `db_backup_freshness_job.rb`; `docs/DR_GUIDE.md:24-29`; `docs/dr_drills.md`; `lib/tasks/dr_verify.rake`.*

**Two honesty notes that must survive editing:**

1. **State the RPO caveat.** `docs/DR_GUIDE.md:314` says plainly: *"Actual RPO is the age of the newest backup, not the 30-minute design."* Publish the 30 minutes with the qualifier *"provided the backup freshness alert is green"*. `DR_GUIDE.md:24-29` already qualifies it this way; do not drop the qualifier in the marketing version.
2. **The drill log shows failures.** `docs/dr_drills.md` records 15 drills between 2026-07-08 and 2026-07-10: **3 passed, 12 failed**, and the final entry failed at 17.5 minutes. The prose above claims only the last *successful* time, which is accurate — but if you offer to walk a prospect through the log, they will see the failures. **Offer it anyway.** A drill programme that fails twelve times and fixes each cause is evidence of a real programme; drills that always pass are evidence of drills that are not hard enough. Have the narrative ready rather than being surprised by the question.

---

## 6. Logging and monitoring

> Every change to a fund, capital call, commitment, distribution, ledger entry, payment or user record is written to an audit log with **the user, the timestamp, and the values before and after the change**. 49 record types are audited. Where support staff act on your behalf, the log names the support user.
>
> Infrastructure is monitored with self-hosted Grafana and Prometheus. AWS GuardDuty and CloudTrail are enabled, with a documented weekly security-event review and triage targets of 24 hours for high and critical findings.
>
> Application logs filter sensitive parameters — passwords, tokens, secrets, certificates, one-time codes, tax identifiers and card data are never written to logs.

*Evidence: `Gemfile:20`; `db/schema.rb:624-644`; `trackable.rb`; `config/initializers/audited.rb:1`; `config/initializers/filter_parameter_logging.rb:6-9`; `config/initializers/observability/`; `docs/security/security_event_review_methodology.md:23-34`; `cybersecurity_risk_management_policy.md:26`.*

**Not claimed:** audit-log immutability (no WORM/append-only), external SIEM shipping, or a defined audit-log retention period. None was found. If asked, say so.

---

## 7. Development and vulnerability management

Write this section only after the CI restoration in the audit's §6 item 7 — otherwise it is false.

> Static security analysis (Brakeman) and dependency vulnerability scanning (bundler-audit) run against the codebase. Module boundaries are enforced automatically. We run documented internal security reviews with severity-graded findings and track remediation.
>
> To report a vulnerability, email **support@caphive.com** marked "Security". We will acknowledge within one business day.

🔴 **TODO — the scanning claim is currently false in CI.** Commit `753216c99` (2026-07-06) deleted `.github/workflows/lint.yml`, which ran Brakeman and bundler-audit. The only remaining workflow runs no security scanning and no tests. **Restore it before publishing this section** — the gems are still installed, so this is cheap. Until then, either omit the section or soften to *"scanned during development"*.

**Not claimed:** third-party penetration testing. `cybersecurity_risk_management_policy.md:49-51` says pen tests occur at least annually and `:55` says results are filed under `docs/security/` — **there is no pen-test report there.** Either produce it or drop the claim from the policy too; an internal policy that describes a control you do not perform is worse than not having the policy.

**Worth publishing, and rare:** *"We publish our internal security review findings to prospects under NDA, including the ones we have accepted as risks rather than fixed."* Five such reviews exist totalling ~2,500 lines, one of which records an accepted risk openly. Very few vendors at this stage will make that offer, and it converts a weakness into the specificity the GTM plan is built on.

---

## 8. Certifications — the section that replaces the badges

> **We do not hold SOC 2 or ISO 27001 today.** We are a young company and we would rather tell you that than let you discover it.
>
> What we can give you instead, today: this page, a completed security questionnaire within one business day, our subprocessor list, a DPA, our recovery-drill log with measured restore times, and a call with the engineer who built the controls rather than a salesperson reading from a sheet.
>
> **SOC 2 Type I is funded from our first US closes**, with the engagement starting after our second US customer signs. We will publish the target date when the engagement is booked rather than before.

*This wording matches the actual plan — `us_gtm_prerequisites.md` §6 and `us_gtm_zero_budget_notes.md` §8, §10 both treat SOC 2 as funded from first closes and explicitly not a blocker for this segment.*

**This section is not a weakness to be buried.** In the $300M–$2B mid-market band the GTM doc targets, the gate is a questionnaire rather than a formal InfoSec review (`us_gtm_zero_budget_notes.md` §8). Candour plus evidence clears that gate. An unverifiable badge does not clear it and creates a misrepresentation problem if the deal reaches contract.

---

## 9. Support commitment (checklist E5)

🔴 **BLOCKED — this is a staffing decision, not a writing task.** The GTM doc §8 proposes *"support until 2pm ET"*, which is India evening and honest. Once decided, publish: actual hours, response targets by severity, and the channel — and keep it consistent with `contact.html` (which currently carries a `TODO` on exactly this and routes support to `hello@caphive.com` as an interim) and with any contractual SLA.

**Do not publish hours you will not staff.** A missed 9am ET capital-call escalation confirms the precise objection this entire plan exists to defuse.

---

## 10. Assembly checklist

- [ ] Remove SOC 2, ISO 27001, TLS 1.3 and SSO claims from `security.html` (lines 43-46, 109-110, 195-217) and from `privacy.html:215`
- [ ] Resolve the EBS encryption and ALB `ssl_policy` verifications; add those sentences only once true
- [ ] Confirm C1 / H1 status before publishing §4's tenant-isolation paragraph
- [ ] Restore the CI security workflow before publishing §7
- [ ] Resolve the GA4 / Clarity question ([`E4_subprocessor_list.md`](E4_subprocessor_list.md) §2) before publishing `cookies.html`
- [ ] Decide and insert the E5 support commitment
- [ ] Link the new `subprocessors.html` from this page
- [ ] Have counsel review, alongside the DPA (E3)
- [ ] Edit into `website_src/pages/security.html` — **not** `public/website/` — and run `rake website:build`
