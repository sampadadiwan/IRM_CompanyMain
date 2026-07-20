# Cybersecurity Risk Management Policy

**Scope:** CapHive platform infrastructure and application code
**Owner:** Engineering
**Review cadence:** Annually, or after any significant security incident

## 1. Purpose

This policy defines how CapHive identifies, monitors, and reduces cybersecurity risk across
our AWS infrastructure and application codebase. It covers network controls, threat detection,
observability, dependency management, and periodic assurance activities.

## 2. Network & Perimeter Controls (AWS Security Groups / Firewall Rules)

- Production and staging run in separate AWS accounts, each with its own network boundary.
- Security groups follow least-privilege: inbound access is restricted to required ports/sources
  only; no security group permits unrestricted (`0.0.0.0/0`) access to administrative ports (SSH,
  RDP, database ports).
- Changes to security group rules go through code review (Pulumi/IaC) rather than manual console edits.
- Rules are reviewed quarterly to remove unused or overly broad entries.

## 3. Threat Detection (AWS GuardDuty)

- GuardDuty is enabled on all AWS accounts (staging and production).
- Findings are routed to an alerting channel monitored by engineering.
- High/Critical severity findings are triaged within 24 hours; Medium within 5 business days.
- GuardDuty findings and remediation are logged for audit purposes.

## 4. Monitoring & Alerting (Grafana)

- Grafana dashboards track application health, error rates, latency, and infrastructure metrics
  for both staging and production.
- Alert rules are configured for anomalous conditions (error spikes, failed logins, resource
  exhaustion) and route to the on-call engineer.
- Dashboards are reviewed after incidents to identify gaps in coverage and add new alerts as needed.

## 5. Dependency & Vulnerability Management

- `bundler-audit` runs as part of the CI pipeline (and/or a scheduled job) to flag known
  vulnerabilities in Ruby gem dependencies.
- Flagged vulnerabilities are triaged: Critical/High severity gems are upgraded promptly;
  Low/Medium are batched into regular maintenance.
- Gems are kept current via routine dependency upgrades, not just when a CVE is flagged, to avoid
  large/risky version jumps later.
- The same discipline applies to JS/npm dependencies where used.

## 6. Periodic Assurance Activities

- **Penetration testing:** conducted periodically (at minimum annually, or before major product
  launches involving new attack surface). Findings are tracked to remediation with owners and
  deadlines.
- **Security code reviews:** security-focused reviews (see `/security-review`) are performed for
  changes touching authentication, authorization, payments, PII, or external integrations, in
  addition to standard code review.
- Results of pen tests and security reviews are documented under `docs/security/` for traceability.

## 7. Incident Response

- Any confirmed security incident is documented, including timeline, impact, and remediation.
- Post-incident, this policy and related alerts/dashboards are updated to close the gap that
  allowed the incident.

## 8. Summary Table

| Control | Tool | Cadence |
|---|---|---|
| Network access control | AWS Security Groups | Reviewed quarterly |
| Threat detection | AWS GuardDuty | Continuous; triage on finding |
| Observability & alerting | Grafana | Continuous |
| Dependency vulnerabilities | bundler-audit | CI on every build |
| Dependency freshness | Gem/npm upgrades | Routine maintenance |
| Penetration testing | Third-party/internal | Annually / major launches |
| Security code review | `/security-review` | Per sensitive change |
