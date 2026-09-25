# Client note — PeerCapital Annual Report email bounces

Ready to send. Plain language, no internal detail. Technical analysis lives in
[`24092026_peercapital_annual_report_email_bounces.md`](24092026_peercapital_annual_report_email_bounces.md).

**Before sending, confirm with the team:** the "send a link instead" option in step 3
requires Data Rooms to be enabled on the PeerCapital account (currently **off**). Either
enable it first, or drop step 3 and leave the fix as the path forward.

---

**Subject:** Annual Investor Report FY 2025-26 — delivery issue and next steps

Hi <name>,

Thank you for flagging the bounce messages. We have investigated and can explain
exactly what happened.

**What happened**

The Annual Investor Report PDF is about 20 MB. Email attachments grow by roughly a
third when they are encoded for sending, so each email left our system at close to
28 MB.

Two things followed from that:

1. Some recipients on corporate email systems could not accept a message that large.
   Many organisations cap incoming email between 10 MB and 25 MB.

2. More significantly, every one of the 137 investor emails was automatically copied
   to `finance@peercapital.in` and `investor.relations@peercapital.in`. That meant each
   of those two mailboxes received 137 copies of a 28 MB email — roughly 3.8 GB each —
   within a few minutes. Google's mail servers could not take that volume that quickly,
   held the messages, retried through the night, and then returned the delivery failure
   notices you saw the following morning.

**What this means**

We have to be straightforward with you: **a large proportion of this send did not get
through.** Counting the investor emails and the two copies of each, the send produced
411 individual deliveries, and approximately 372 of those failed. Many of the failures
are your own copies rather than investors — but on any reading, a significant number of
investors did not receive the report.

**We cannot currently tell you which specific investors were affected.** The delivery
feedback channel between our email provider and CapHive was not switched on at the time,
so the failures were counted but not recorded against individual recipients. We are
fixing that, but it cannot be applied retrospectively to this send.

There is one exception we can confirm: **Prashant Mishra (prashant@agnam.in) was not
sent the email at all**, because email notifications are switched off on his investor
record in CapHive. That is a setting rather than a failure, and you may want to review it.

**How we can get you the exact list**

Every failure notice was returned to `investor.relations@peercapital.in`, and each one
names the recipient it failed for. If you search that mailbox for messages from
MAILER-DAEMON on 24 September between roughly 10:00 and 11:00, you will have the
definitive list. In Gmail:

```
from:mailer-daemon after:2026/09/23 before:2026/09/25
```

If you forward those to us, we will reconcile them against the investor list and tell
you exactly who needs a re-send.

Your email sending reputation has not been affected. We checked it directly with our
email provider: the account is rated **Healthy**, with a bounce rate of 0.01%. There is
no risk to your ability to send email from CapHive.

**What we would ask you to do**

1. **Please do not re-send this notification as it stands.** The attachment is still
   20 MB, so re-sending would repeat the same problem.

2. **In the meantime, the report is already available in the CapHive investor portal.**
   Any investor can sign in and download it directly, and the emails that did arrive
   included a link to it. This is the quickest route for anyone who asks.

3. **We would recommend re-sending the report to the full investor list**, using a
   secure download link in place of the attachment. The link opens the document without
   requiring a login and stays valid for 30 days. Because we cannot identify exactly who
   missed it, sending to everyone is the safest course — and with a link rather than a
   20 MB file, a full re-send carries none of the risk the original did. We can set this
   up for you; please just confirm you would like us to.

**What we are changing**

Three things:

- Documents above a safe size will never be attached to an email. The message will carry
  a secure download link automatically instead.
- A bulk notification will send your team a single summary email rather than one copy per
  investor, so your own mailboxes are never flooded again.
- We are connecting the delivery-feedback channel from our email provider into CapHive,
  so that bounces are recorded against individual recipients and visible to you on screen.
  Had this been in place, we could have told you within minutes exactly who had not
  received the report.

We are sorry for the disruption. Please let us know if you would like us to re-send the
report using the link method, and we will arrange it.

Best regards,
<name>
