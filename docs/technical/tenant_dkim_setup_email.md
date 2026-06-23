# Tenant Email — DKIM/SPF Setup Required

Subject: Action needed - email authentication setup for [Tenant Domain] (prevents spam/bounce issues)

Hi [Tenant Contact],

Summary
Some emails sent from [tenant domain] through our platform are being flagged by recipients' mail providers (Gmail, Outlook, etc.) as "not authenticated." This happens because the domain hasn't yet been set up with standard email authentication (DKIM/SPF). We can fix this with a small DNS change on your end - no changes to our platform are required.

Business impact
- Some recipients see a caution warning on otherwise legitimate emails (capital calls, statements, distribution notices), which can reduce trust and slow down responses.
- A subset of recipients - particularly at companies with strict email security policies - may not receive these emails at all; they get silently rejected ("bounced") rather than delivered.
- This risk grows over time, as major providers (Gmail, Yahoo) have been tightening these requirements industry-wide.

The fix
This is a one-time DNS configuration change for [tenant domain]. Once your IT team adds the records below, our platform's outgoing mail will be cryptographically signed and verified by recipient mail servers - resolving both the warning and the bounce risk.

Timeline
- Adding the records typically takes IT under 15 minutes.
- DNS changes can take anywhere from a few minutes up to 24-48 hours to fully propagate, depending on your DNS provider.
- Once propagated, we'll confirm verification on our side (usually same day) and the warning will stop appearing on new emails.

We've attached the DKIM keys as a CSV, along with the technical details below for your IT team. Happy to hop on a call with them if useful.

Thanks,
[Your name]

---

Technical details (for IT)

We use Amazon SES to send mail on behalf of [tenant domain]. To authenticate this domain, please add the following DNS records:

1. DKIM
   See the attached CSV for the exact CNAME records to add. These are domain-specific keys generated for [tenant domain] and must be added exactly as provided.

2. SPF - add (or update if one already exists - a domain can only have one SPF record) a TXT record:
   Type: TXT
   Host: [tenant domain]
   Value: v=spf1 include:amazonses.com ~all

   If you already send mail from this domain via another service (Office 365, Google Workspace, etc.), merge that service's include: into the same record rather than adding a second SPF record - multiple SPF records will break validation.

3. DMARC (recommended) - add a TXT record:
   Type: TXT
   Host: _dmarc.[tenant domain]
   Value: v=DMARC1; p=quarantine; rua=mailto:[IT contact]@[tenant domain]

   Start with p=quarantine (or p=none for monitoring-only initially) rather than p=reject, to avoid risk of legitimate mail being blocked while this rolls out.

Once these are live, we'll verify domain and DKIM status in the SES console and confirm back to you. No changes are needed on our side or in how you currently interact with the platform.
