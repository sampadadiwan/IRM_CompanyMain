# E2 — Pre-Completed Security Questionnaire

**Checklist row:** E2 · **Done when:** a PDF that can be sent within an hour of a request
**Status:** **DRAFTED — must not be sent until the 🔴 items are resolved.**

**Format:** structured on the SIG Lite / CAIQ domain model so answers can be transcribed into whichever form a prospect sends. Most mid-market GPs send a 20–40 question spreadsheet, not a full SIG; this covers the union of what those ask.

---

## How to use this — read before sending

1. **Every 🔴 answer is blocked** on a verification in [`E_SECURITY_CLAIMS_AUDIT.md`](E_SECURITY_CLAIMS_AUDIT.md). Sending this document with a 🔴 unresolved means putting an unverified statement in writing to a fund's General Counsel.
2. **Never upgrade an answer to make it look better.** The answers below are deliberately calibrated. A "No, and here is what we do instead" is recoverable; a "Yes" that turns out to be a "No" ends the deal and, in a signed questionnaire, is a contractual misrepresentation.
3. **Answer format is deliberate:** direct answer first, then the mechanism, then the limitation. Prospects' security reviewers read hundreds of these; the ones that lead with the limitation instead of burying it get trusted.
4. **When something is genuinely unknown, write "we will confirm and come back to you within one business day" — then do.**

---

## A. Company and scope

| # | Question | Answer |
|---|---|---|
| A1 | Legal entity name and jurisdiction | 🔴 **TODO-HUMAN.** The Indian entity today; a Delaware entity is planned (checklist G1). State whichever will sign the contract. |
| A2 | What service is provided? | Fund operations software for private markets: fund accounting, investor onboarding, capital calls and distributions, portfolio monitoring, LP reporting, deals and secondaries. |
| A3 | Do you use subcontractors/subprocessors? | Yes. A full list is maintained and provided — see [`E4_subprocessor_list.md`](E4_subprocessor_list.md). |
| A4 | Named security contact | `support@caphive.com`, marked "Security". 🔴 **TODO-HUMAN:** name an individual owner. |
| A5 | Do you have cyber liability insurance? | 🔴 **TODO-VERIFY.** No evidence in the repository. Answer honestly; if none, say so — it is a common gap at this stage and is often satisfied by committing to obtain it before go-live. |

## B. Certifications and audits

| # | Question | Answer |
|---|---|---|
| B1 | SOC 2 Type I or II? | **No.** We do not hold a SOC 2 report today. A Type I engagement is funded from our first US closes and will begin after our second US customer signs. We will share the target date once the engagement is booked. |
| B2 | ISO/IEC 27001 certified? | **No.** |
| B3 | Third-party penetration test in the last 12 months? | **No third-party penetration test report exists.** We run documented internal security reviews with severity-graded findings — five to date, ~2,500 pages of analysis — and will share them under NDA, including findings we have accepted as risks rather than fixed. We will accommodate a client-run penetration test against a non-production environment, scoped in writing. |
| B4 | Do you undergo independent audit of controls? | Not currently. See B1. |
| B5 | Will you complete our questionnaire and re-attest annually? | Yes. |

> **Do not soften B1–B3.** The current website claims SOC 2 Type II and ISO 27001 with no supporting evidence — see the audit document. A questionnaire answer that contradicts the website is worse than either alone, so **the website must be corrected before this questionnaire is sent.**

## C. Hosting and infrastructure

| # | Question | Answer |
|---|---|---|
| C1 | Where is the service hosted? | Amazon Web Services. Three regions: Mumbai (ap-south-1), Hyderabad (ap-south-2), N. Virginia (us-east-1). |
| C2 | Can data residency be guaranteed? | Yes — region is agreed at implementation. **US clients are served from us-east-1 and their application data stays in that region.** Note the exceptions in G3 (some subprocessors are outside the region). |
| C3 | Are production and non-production separated? | Yes — **separate AWS accounts** (production and staging), each with its own network boundary, credentials, and infrastructure state. |
| C4 | Is production data used in non-production? | 🔴 **TODO-VERIFY.** Not determinable from the repository. Confirm before answering. |
| C5 | Managed database service? | **No** — MySQL 8.4 LTS, Redis and Elasticsearch are self-hosted on EC2 instances in private subnets, not RDS/ElastiCache/OpenSearch. The database is not reachable from the internet. |
| C6 | Is infrastructure defined as code? | Yes — Pulumi for infrastructure, Packer for machine images, Capistrano for application deploys. |
| C7 | Is there a WAF? | Yes — AWS WAFv2 with managed rule sets: IP reputation, common attacks, known-bad inputs, Linux rules, SQL injection; plus a custom IP blocklist. |
| C8 | Rate limiting / DDoS protection? | Application-level rate limiting (Rack::Attack) in all environments, covering login brute-force and endpoint scanning, applied to authenticated and unauthenticated traffic. AWS Shield Standard via the load balancer. |
| C9 | Is a CDN used? | No. Static assets are served by nginx on the application servers. |

## D. Encryption

| # | Question | Answer |
|---|---|---|
| D1 | Encrypted in transit? | Yes. TLS terminates at the load balancer; the application refuses non-HTTPS requests and sets HSTS. Session cookies are `secure` and `httpOnly`. Outbound mail uses STARTTLS. |
| D2 | Minimum TLS version? | 🔴 **BLOCKED.** The load balancer listener pins no TLS policy, so the AWS default currently permits TLS 1.0. **Do not answer "TLS 1.2+" until `ELBSecurityPolicy-TLS13-1-2-2021-06` is pinned and verified.** This is a one-line infrastructure change; make it before sending. |
| D3 | Encrypted at rest? | **Partially, and stated precisely:** documents and all database backups are in Amazon S3 with AES-256 server-side encryption, versioned and cross-region replicated. 🔴 **Database volume encryption is unconfirmed** — no EBS volume in our infrastructure code sets an encryption flag. Verify in the AWS console before answering. **Do not answer an unqualified "yes".** |
| D4 | Field-level encryption of sensitive data? | **No.** Application-level encryption is configured but currently protects only the MFA secret. Bank details, tax identifiers and KYC fields are not column-encrypted; they are protected by access control, network isolation and storage-layer encryption. |
| D5 | Key management? | Infrastructure secrets in AWS SSM Parameter Store as KMS-encrypted SecureStrings, with decryption scoped to the service. Application secrets in encrypted credential files with a separate key per environment, injected at deploy and never committed. |
| D6 | Password storage? | bcrypt, cost factor 12. |
| D7 | Encrypted backups? | Yes — AES-256 server-side encryption in S3. |

## E. Access control

| # | Question | Answer |
|---|---|---|
| E1 | Authentication method | Email and password, with optional multi-factor authentication. |
| E2 | Password policy | Minimum 8 characters, maximum 128, bcrypt cost 12. Account lockout after 6 failed attempts with automatic unlock after 5 minutes. Password reset links expire after 6 hours. **No complexity, rotation, history or expiry requirements are enforced.** |
| E3 | Is MFA available? | **Yes, for every user, with three second factors:** authenticator app (TOTP, RFC 6238), WhatsApp, or SMS. There are no backup codes; recovery is an audited administrator reset that emails the account holder. |
| E4 | Is MFA enforced? | **No — it is available and opt-in per user.** There is no organisation-wide enforcement setting today. If mandatory MFA is a requirement for your firm, tell us; it is on the roadmap. |
| E5 | SAML / SSO federation (Okta, Entra ID)? | **No.** We do not support federated SSO today. We are an OAuth 2.0 / OpenID Connect **provider** for API and AI-client access (authorization-code flow, PKCE required, HTTPS-only redirect URIs) — that is a different capability and we do not want it mistaken for SSO. Federated SSO is our most-requested security roadmap item. |
| E6 | Session timeout | 60 minutes. |
| E7 | RBAC granularity | Role-based access control to record-type level, with granular per-permission flags. 153 distinct authorization policies enforced across the platform. |
| E8 | **How is one client's data isolated from another's?** | Each client is a separate tenant, resolved from the request. Authorization is enforced globally, not per-feature: every action must declare a policy and every listing must apply a tenant scope, or the request fails. The base policy **denies by default**. Records outside your tenant return "not found" rather than "not permitted", so probing cannot confirm another tenant's records exist. **Architecture is a shared database with row-level tenancy, not a database per tenant** — we state that plainly because it determines the follow-up questions. 🔴 **See the blocking note below.** |
| E9 | Can vendor staff access client data? | **Not by default.** Access requires a named mapping between a specific support user and your entity, which **you enable and can withdraw at any time**. When support acts on your behalf the audit trail records the support user, not the client user. |
| E10 | Privileged/administrative access controls | 🔴 **BLOCKED — do not claim restriction.** SSH is currently open to `0.0.0.0/0` on application servers with key-only authentication and no bastion. **Never answer "restricted to bastion/VPN".** Either restrict it before sending (recommended — it is a security-group change) or answer honestly: "key-only SSH authentication; network restriction to a bastion is in progress." |
| E11 | Access reviews | 🔴 No documented user access-review procedure exists. Security groups are reviewed quarterly. Answer honestly or institute the procedure first. |
| E12 | Offboarding | 🔴 **TODO-VERIFY.** No documented procedure found. |

🔴 **Blocking note on E8.** Our internal review `docs/security/security_review_2026_07.md` records (a) an **accepted risk** that the support role retains cross-tenant access after switching context, and (b) an **open Critical finding** — an `eval`-based formula engine — whose own analysis states that because tenants share application processes, code execution in one tenant is a path to other tenants' data. **Confirm the current remediation status of that finding before answering E8 in writing.** If it is open, the honest answer must disclose it, and it should be fixed first.

## F. Logging, monitoring, incident response

| # | Question | Answer |
|---|---|---|
| F1 | Is there an audit trail? | Yes. Every change to a fund, capital call, commitment, distribution, ledger entry, payment or user record is logged with user, timestamp, and **before-and-after values**. 49 record types are audited. |
| F2 | Audit log immutability | **Not implemented.** Logs are stored in the application database. No WORM or append-only storage, and no external SIEM shipping. |
| F3 | Audit log retention | 🔴 **TODO-VERIFY.** No defined retention period found. |
| F4 | Infrastructure monitoring | Self-hosted Grafana and Prometheus with committed dashboards and alert rules. AWS GuardDuty and CloudTrail enabled. |
| F5 | Security event review | Documented weekly review across GuardDuty, CloudTrail, Grafana and IAM, with one year of evidence retention. Triage targets: 24 hours for high/critical GuardDuty findings, 5 business days for medium. |
| F6 | Incident response plan | Yes — documented: detect and contain, assess, notify, remediate, review. Production exceptions are captured automatically and root-caused through a documented RCA process with written RCA documents per incident. |
| F7 | Breach notification commitment | 🔴 **TODO-HUMAN — counsel.** Must match the DPA (E3). GDPR obliges a processor to notify the controller "without undue delay"; 72 hours is the common contractual commitment. Do not state a number before counsel confirms it. |
| F8 | Are sensitive values kept out of logs? | Yes — passwords, tokens, secrets, certificates, one-time codes, tax identifiers and card data are filtered from application logs. |

## G. Data handling and privacy

| # | Question | Answer |
|---|---|---|
| G1 | What personal data is processed? | Investor and user identity data (name, email, phone, address), KYC/AML documentation and identifiers, bank account details for distributions, and the fund/portfolio data our clients enter. |
| G2 | Is a DPA available? | 🔴 **In preparation** (checklist E3, requires counsel). |
| G3 | Cross-border transfers | **Yes, and this must be disclosed.** Application data stays in the client's chosen region, but several subprocessors operate elsewhere: LLM providers (US), e-signature and KYC/AML providers (India or US depending on provider), and messaging providers. Our support and engineering team is in India. 🔴 **TODO-HUMAN — counsel:** confirm the transfer mechanism relied on (Standard Contractual Clauses). |
| G4 | **Is client data sent to AI/LLM providers?** | **Yes — this is the question to answer proactively rather than wait for.** Our AI features send prompt content to OpenAI, Anthropic and Google, and route some requests via OpenRouter. Prompts can contain fund, portfolio, KPI and document data. 🔴 **TODO-VERIFY: confirm whether zero-retention / no-training terms are in place with each provider, and state the actual position.** If the answer is "default API terms", say so. This is the first question a fund CFO asks about AI, and getting caught being vague on it is fatal. |
| G5 | Data retention and deletion | 🔴 **TODO-HUMAN.** Not defined. `privacy.html` has `[period]` placeholders. The one figure that is real: **backups are retained 90 days**, so deleted data persists in backups for up to 90 days. State that; it is a normal and defensible answer. |
| G6 | Data export on termination | 🔴 **TODO-VERIFY.** The platform has extensive export capability; whether a contractual exit-assistance commitment exists is a commercial question. |
| G7 | Is data used to train models or for any secondary purpose? | 🔴 Depends on G4. Answer only after G4 is confirmed. |
| G8 | Analytics/tracking in the authenticated application | 🔴 **BLOCKED — do not answer until resolved.** The application currently loads Google Analytics and Microsoft Clarity (session recording) on authenticated pages, tagged with the client entity's name — while `cookies.html` states the opposite. See [`E_SECURITY_CLAIMS_AUDIT.md`](E_SECURITY_CLAIMS_AUDIT.md) §2. **Resolve before any questionnaire is sent.** Recommended resolution is removal, which makes this answer a clean "no". |

## H. Business continuity

| # | Question | Answer |
|---|---|---|
| H1 | Backup frequency | Full nightly at 23:00; incrementals every 30 minutes. |
| H2 | Backup retention | 90 days. Versioned, cross-region replicated. Delete markers are deliberately not replicated, so a deletion in the primary region cannot propagate to the replica. |
| H3 | **RPO** | 30 minutes, set by the incremental cadence — valid while our backup-freshness alerting is green. Actual RPO at any moment is the age of the newest backup. |
| H4 | **RTO** | Approximately 10 minutes for a staging-sized dataset, scaling with database size. Most recent successful drill: **8.7 minutes**, including automated verification. |
| H5 | **Are restores tested?** | **Yes, and logged.** Recovery drills are run against real backups with measured times, recorded in a drill log we will share. Every recovery ends with an automated verification proving the application is serving, database and search are reachable, replication is flowing and backups are armed. **Our drill log includes failed drills as well as successful ones** — we would rather show you a real programme than a clean one. |
| H6 | Database redundancy | MySQL primary with a cross-availability-zone replica. |
| H7 | Documented DR plan | Yes — a full runbook plus a 19-point DR review programme. |

> H1–H7 is the strongest section in this document. **Lead the conversation here.** Very few vendors of this size can produce measured restore times from a logged drill programme, and it directly answers the "what if this fails mid-adoption" objection in the GTM plan §8.

## I. Secure development

| # | Question | Answer |
|---|---|---|
| I1 | Static analysis / dependency scanning | Brakeman (static analysis) and bundler-audit (dependency vulnerabilities) are configured. 🔴 **They are not currently running in CI** — the workflow was removed on 2026-07-06. **Restore it before answering "yes"**, or answer "run during development, CI integration being restored". |
| I2 | Code review before release | 🔴 Mixed — no branch protection or CODEOWNERS. Some changes go through pull requests, some are direct to `main`. Institute branch protection before claiming this. |
| I3 | Dependency update process | 🔴 No Dependabot or Renovate. Manual. |
| I4 | Separate environments | Yes — separate AWS accounts for production and staging. |
| I5 | Secrets management | Encrypted credentials per environment; infrastructure secrets in SSM. 🔴 **Note:** a deploy SSH private key remains committed in the repository (documented internally, history not purged). Rotate before this question is asked. |
| I6 | Content Security Policy | **Not implemented.** The authenticated application loads several third-party CDN assets without CSP or Subresource Integrity. This is a known gap on our roadmap. |
| I7 | Vulnerability disclosure | `support@caphive.com` marked "Security". 🔴 No formal published policy or SLA for reported vulnerabilities; GuardDuty findings have a 24-hour high/critical target. |

---

## J. Pre-send checklist

**Do not send this document until every box is ticked.**

- [ ] Website corrected — SOC 2, ISO 27001, TLS 1.3 and SSO claims removed (else the questionnaire contradicts the site)
- [ ] EBS encryption verified in both production AWS accounts → finalise **D3**
- [ ] ALB `ssl_policy` pinned and verified → finalise **D2**
- [ ] SSH `0.0.0.0/0` restricted, or **E10** answered honestly
- [ ] Critical finding C1 status confirmed → finalise **E8**
- [ ] LLM provider retention/training terms confirmed → finalise **G4** and **G7**
- [ ] GA4 / Clarity in the authenticated app resolved → finalise **G8**
- [ ] CI security workflow restored → finalise **I1**
- [ ] Counsel has confirmed **F7** (breach notification), **G3** (transfer mechanism), **G5** (retention)
- [ ] Contracting entity confirmed → **A1**
- [ ] Legal review of the whole document
- [ ] Exported to PDF, version-numbered and dated

**Then:** keep it as a living document. Re-verify quarterly, and re-issue whenever a 🔴 resolves or a subprocessor changes. The E2 done-when test is "a PDF that can be sent within an hour of a request" — that is only true if it is kept current, not if it is regenerated under pressure.
