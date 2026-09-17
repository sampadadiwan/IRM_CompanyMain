# Custom Notifications User Guide

Custom notifications are your own email templates: each one replaces the wording of one automatic CapHive email (a KYC request, a call notice, a document email, a deal stage update and so on) or defines an ad-hoc email you send yourself, with placeholders, attachments and an optional WhatsApp text.

> **Where to find it:** Every kind is created from the screen it belongs to. Company-wide KYC and agreement templates: Sidebar → [**Funds → KYCs**](/investor_kycs) → **New KYC** → **Custom KYC Notification** or **Custom Agreement Notification** (**View All Custom Notifications** lists the KYC ones). Fund, call and distribution templates: the fund's **Notifications** tab or the call's / distribution's **Notification** tab → **New Notification**. Deals, secondary sales, approvals and investment opportunities have their own **Custom Notifications**, **Notification** or **Notifications** tab. All templates in one list: Profile menu → **My Inbox** → **Custom Notifications**. Company-wide templates need the Company Admin role; the others also accept create access on the fund, deal, sale or approval.

---

## Table of Contents

1. [What a Custom Notification Is](#what-a-custom-notification-is)
2. [All Kinds of Custom Notification](#all-kinds-of-custom-notification)
3. [Custom KYC Notification](#custom-kyc-notification)
4. [Custom Agreement Notification (Document Notification)](#custom-agreement-notification-document-notification)
5. [Investment Opportunity Notifications](#investment-opportunity-notifications)
6. [Fund Notifications (Ad-hoc)](#fund-notifications-ad-hoc)
7. [Call and Distribution Notifications](#call-and-distribution-notifications)
8. [Deal Notifications](#deal-notifications)
9. [Secondary Sale Notifications](#secondary-sale-notifications)
10. [Approval Notifications](#approval-notifications)
11. [Seeing All Custom Notifications](#seeing-all-custom-notifications)
12. [The Notification Form](#the-notification-form)
13. [Placeholders (Variables)](#placeholders-variables)
14. [Attachments](#attachments)
15. [Which Notification Is Used](#which-notification-is-used)
16. [Previewing and Testing](#previewing-and-testing)
17. [Editing, Disabling, Deleting and Restoring](#editing-disabling-deleting-and-restoring)
18. [Frequently Asked Questions](#frequently-asked-questions)
19. [Related Guides](#related-guides)

---

## What a Custom Notification Is

Out of the box, every email CapHive sends has standard wording. A custom notification (users also call it an *email template*, *notification template* or *custom email*) lets you:

- **Replace one automatic email** — pick the email in **For Notification** (for example **Kyc required reminder** or **Notify capital remittance**) and write your own subject and body. Every other email keeps its standard text.
- **Send an ad-hoc email** — for a fund (**Adhoc fund notification**, **Adhoc kyc notification**) or a secondary sale (**Adhoc notification**) you write a message and send it yourself from that record.
- **Personalise** each email with placeholders such as `{{investor_name}}`, add attachments, and add a short WhatsApp message.

A custom notification belongs to one *owner*: your company (KYC, agreement/document and investment opportunity templates), a fund, a capital call, a capital distribution, a deal, a secondary sale or an approval. It only affects emails sent for that owner.

---

## All Kinds of Custom Notification

| Kind (screen label) | Where you create it | Used for | Level |
|---|---|---|---|
| **Custom KYC Notification** (form title *KYC Notification*) | [**Funds → KYCs**](/investor_kycs) → **New KYC** → **Custom KYC Notification** | The automatic KYC emails: KYC required (first link), KYC reminder, updates requested, KYC updated and KYC submitted. Tagged reminder templates also add **Send Reminder <tag>** bulk actions | Company |
| **Custom Agreement Notification** / **Document Notification** (form title *Document Notification*) | **New KYC** → **Custom Agreement Notification**, or **My Inbox** → **Custom Notifications** → **New Notification** → **Document Notification** | The email sent with **Send Document** on a document page and **Email Using Template:** on a filtered documents list, with the document attached — typically agreements and KYC documents | Company |
| Investment opportunity notification (form title *Investment Opportunity Notification*) | Open any opportunity → **Notifications** tab → **New Notification** → **New Custom Notification** | Replaces the "open for interests" and "allocated" emails, and adds a **Send <subject>** item to every opportunity's **Notifications** menu | Company |
| **New Fund Notification** | Fund → **Notifications** tab → **New Notification** → **New Fund Notification** | An ad-hoc email you send with **Send Notification**, one per commitment (**Adhoc fund notification**) or one per investor KYC (**Adhoc kyc notification**) | Fund |
| **New Call Notification** | Fund → **Notifications** tab (fund-wide default), or a call's **Notification** tab (that call only) | Call notice, call reminder and payment-received emails | Fund default / Call |
| **New Distribution Notification** | Fund → **Notifications** tab (fund-wide default), or a distribution's **Notification** tab (that distribution only) | The distribution payment email | Fund default / Distribution |
| Deal notification | Deal → **Custom Notifications** tab → **New Notification** → **New Custom Notification** | The "Deal Update: … moved to stage" email when an investor moves to a new deal step | Deal |
| Secondary sale notification | Sale → **Notification** tab → **New Notification** → **New Custom Notification** | Replaces the sale's emails (open / closing for offers or interests, allocation, SPA) or defines an **Adhoc notification** to a group sent from the sale's **Notifications** menu | Secondary sale |
| Approval notification | Approval → **Notification** tab → **New Notification** → **New Custom Notification** | Replaces the approval activation, reminder and response emails | Approval |

---

## Custom KYC Notification

A company-wide template for the KYC emails. Create it from Sidebar → [**Funds → KYCs**](/investor_kycs) → **New KYC** → **Custom KYC Notification**. In **For Notification** pick the email it replaces:

| For Notification | Replaces | Sent to |
|---|---|---|
| **Notify kyc required** | "Request to add KYC" — the first email with the 30-day link to fill in the KYC | The stakeholder's users |
| **Kyc required reminder** | "Reminder to update KYC" — sent by **Send KYC Reminders**, **Bulk Actions → Send Reminder** and **KYC Actions → Send KYC Reminder** | The stakeholder's users |
| **Notify updates requested** | The "please update your KYC" email when you click **Request Updates** (also the note to your team when an investor asks for updates) | The stakeholder's users / your team |
| **Notify kyc updated** | "KYC updated for …" | Your employees with the KYCs feature |
| **Notify kyc submitted** | "KYC submitted by …" | Your employees with the KYCs feature |

**Several templates for the same email.** You can keep more than one template per email and tell them apart with **Tag** (for example `SEBI` and `GIFT`):

- On a filtered KYC list, **Bulk Actions** shows one **Send Reminder <tag>** item per **Kyc required reminder** template instead of the plain **Send Reminder**.
- On a KYC record, **KYC Actions** shows **Send KYC Required Notification (<tag>)** and **Send KYC Reminder (<tag>)** per template, and **Preview Notifications** shows matching preview items.
- Sends that don't name a template (for example **Send KYC Reminders** on the unfiltered list, **Request Updates**, or the first KYC link sent when a KYC is created or imported with the form to be sent) use the most recently created enabled template for that email.

**Not the same as a fund's Adhoc kyc notification.** A Custom KYC Notification changes the wording of the standard KYC workflow emails for the whole company. A fund's **Adhoc kyc notification** (see [Fund & Commitment Notifications](fund_commitment_notifications_user_guide)) is a free-form message you send yourself from one fund to the investor KYCs linked to it.

---

## Custom Agreement Notification (Document Notification)

A company-wide template for emailing a document. It is the same kind of template whether you start from **New KYC** → **Custom Agreement Notification** or from **My Inbox** → **Custom Notifications** → **New Notification** → **Document Notification**; its only email is **Send document**.

Once enabled, each template appears:

- on a document's page, in the **Send Document** menu as **Send <subject>**; and
- on a filtered documents list, in **Actions** under **Email Using Template:**, labelled with its subject (see [Document Management](document_management_user_guide)).

Sending emails the document itself as an attachment to every user who has access to that document (**View Who Gets Notified** in the confirmation shows them). A generated document must be approved first, and a document nobody has access to fails with "No users to send". Files uploaded on the template's own **Documents** tab are attached as well.

---

## Investment Opportunity Notifications

Company-wide templates for investment opportunity emails. Open any opportunity → **Notifications** tab → **New Notification** → **New Custom Notification**; every opportunity shares the same list. **For Notification** offers **Notify open for interests** and **Notify allocation**.

- An enabled template replaces the wording of **Send Investment Opportunity Open : To LPs** or **Send Investment Opportunity Allocated : To LPs** for its email.
- Each enabled template also appears in every opportunity's **Notifications** menu as **Send <subject>**, which emails all investors with access using that template.

See [Investment Opportunities](investment_opportunity_user_guide).

---

## Fund Notifications (Ad-hoc)

A fund-owned template you send yourself. Fund → **Notifications** tab → **New Notification** → **New Fund Notification**, choose **Adhoc fund notification** (one email per commitment, attachments from the commitment) or **Adhoc kyc notification** (one email per investor KYC linked to the fund, attachments from the KYC), save, then open it and click **Send Notification**. The full workflow is in [Fund & Commitment Notifications](fund_commitment_notifications_user_guide).

---

## Call and Distribution Notifications

These templates replace the capital call and distribution emails:

| Template | For Notification choices |
|---|---|
| **New Call Notification** | **Notify capital remittance** (call notice), **Reminder capital remittance** (call reminder), **Notify capital remittance payment** (payment received) |
| **New Distribution Notification** | **Send notification** (distribution payment email) |

Create them at two levels:

- **Fund-wide default** — fund → **Notifications** tab → **New Notification** → **New Call Notification** or **New Distribution Notification**. Used by every call or distribution in that fund that has no template of its own for that email.
- **One call or distribution** — open the call or distribution → **Notification** tab → **New Notification** → **New Call Notification** / **New Distribution Notification**. If the fund already has a default for the email you pick, the form warns that saving overrides it for this record.

Call notice, call reminder and distribution emails always attach the record's approved generated notice and any manually uploaded documents, whatever **Attachment names** says. The **Show details** switch adds the call or distribution breakdown table to the email. See [Capital Calls](capital_calls_user_guide) and [Capital Distributions](capital_distributions_user_guide).

---

## Deal Notifications

Open the deal → **Custom Notifications** tab → **New Notification** → **New Custom Notification** and choose **Deal activity move**. When an investor moves to a new deal step and the deal and step are set to notify (see [Deals Management](deals_management_user_guide)), the "Deal Update" email uses your template instead of the standard text. Put a step's title in **Tag** to use a template for that step only; a template with no tag covers every other step. The **Adhoc notification** choice on a deal has no send button, so it is never sent.

---

## Secondary Sale Notifications

Open the sale → **Notification** tab → **New Notification** → **New Custom Notification**.

- **Replace a sale email** — pick **Notify open for offers**, **Notify closing offers**, **Notify open for interests**, **Notify closing interests**, **Notify allocation offers**, **Notify allocation interests**, **Notify spa offers** or **Notify spa interests**. The sale's own sends of that email use your wording.
- **Ad-hoc message to a group** — pick **Adhoc notification** and choose **To**: **All Sellers**, **Verified Sellers**, **Approved Sellers**, **All Buyers** or **Shortlisted Buyers**. Each such template appears by subject at the bottom of the sale's **Notifications** menu; clicking it emails that group. Choose a **To** group — a template with none sends nothing.

See [Secondary Sales](secondary_sales_user_guide).

---

## Approval Notifications

Open the approval → **Notification** tab (shown to users who can update the approval) → **New Notification** → **New Custom Notification**, and choose **Notify new approval**, **Approval reminder** or **Notify approval response**. The dropdown also lists **Attach all docs** and **Update notification sent**; these are not emails, so don't pick them. See [Approvals](approvals_user_guide).

---

## Seeing All Custom Notifications

- **Every template in your company:** Profile menu → **My Inbox** → **Custom Notifications** (the button is shown to employees). The list shows **Email**, **Subject**, **Whatsapp**, **For** (type and owner), **Enabled** and **Latest**, with a **Filter** panel. Its **New Notification** menu offers **Document Notification**.
- **KYC templates only:** [**Funds → KYCs**](/investor_kycs) → **New KYC** → **View All Custom Notifications**.
- **Per record:** the fund's **Notifications** tab, a call's or distribution's **Notification** tab, a deal's **Custom Notifications** tab, a sale's or approval's **Notification** tab, and an opportunity's **Notifications** tab.

The full lists opened from **My Inbox**, **View All Custom Notifications**, the fund's **Notifications** tab and the deal's **Custom Notifications** tab open for Company Admins; other users get an access error there. Call, distribution, opportunity, sale and approval tabs show their templates to anyone who can open that page.

---

## The Notification Form

The form opens as a **Guided Wizard** (switch to **Classic Form** at any time) with five steps: **What to Expect**, **Notification & Recipients**, **Compose Message**, **Attachments & Options**, **Review & Save**.

| Field | What it does |
|---|---|
| **For Notification** | The email this template replaces or, for ad-hoc kinds, the kind of ad-hoc send. The choices depend on the kind (see the sections above). |
| **To** | Secondary sale **Adhoc notification** only: the group that receives it. |
| **Tag** | Internal label (up to 30 characters). Shown after KYC reminder labels, used as the step title for deal templates. Recipients never see it. |
| **Subject** | The email subject, used as typed. Placeholders are not replaced in the subject. |
| **Body** | The email body. **+ Insert placeholder…** adds tokens such as `{{investor_name}}`. An empty body means no email is sent at all. |
| **WhatsApp** | Short plain-text message sent over WhatsApp where enabled. Avoid & ^ # ` ~. Blank means no WhatsApp message. |
| **Show details** | Calls and distributions only: adds the breakdown table to the email. |
| **Attachment names** | Documents to attach by name (see [Attachments](#attachments)). |
| **Only attach the latest match** / **Attachment mandatory** | Appear once **Attachment names** has text. |
| **Show details link** | Adds the "View …" / "Login to Access" link at the bottom of the email. On by default. |
| **Template enabled** | Off keeps the template saved but unused, so the standard email is sent. |
| **Dynamic Template** | CapHive support only: renders the body as a code template. |

---

## Placeholders (Variables)

Pick placeholders from **+ Insert placeholder…**; the list changes with **For Notification**. A mistyped token is sent as plain text. Every kind has `{{user_full_name}}`, `{{user_first_name}}`, `{{user_last_name}}`, `{{user_email}}` (the recipient) and `{{entity_name}}` (your company). Extra placeholders:

| Kind | Extra placeholders |
|---|---|
| Custom KYC Notification | `{{investor_name}}` (KYC full name), `{{fund_name}}` (your company's name), `{{committed_amount}}` |
| Custom Agreement / Document Notification | `{{document_name}}`, `{{kyc_full_name}}`, `{{folio_id}}`, `{{committed_amount}}` (last two for commitment documents) |
| Investment opportunity | `{{company_name}}`, `{{fund_name}}` |
| Fund — Adhoc fund notification | `{{investor_name}}`, `{{fund_name}}`, `{{folio_id}}`, `{{kyc_full_name}}`, `{{committed_amount}}` |
| Fund — Adhoc kyc notification | `{{investor_name}}`, `{{fund_name}}`, `{{kyc_full_name}}` |
| Call notice / reminder | `{{investor_name}}`, `{{fund_name}}`, `{{capital_call_name}}`, `{{call_amount}}`, `{{remittance_amount}}`, `{{due_date}}`, `{{folio_id}}`, `{{kyc_full_name}}`, `{{committed_amount}}` |
| Call payment received | as above without due date and call amount, plus `{{payment_amount}}` |
| Distribution | `{{investor_name}}`, `{{fund_name}}`, `{{net_payable_amount}}`, `{{folio_id}}`, `{{kyc_full_name}}`, `{{committed_amount}}` |
| Deal | `{{deal_name}}`, `{{investor_name}}` |
| Secondary sale | `{{secondary_sale_name}}` |
| Approval | `{{approval_title}}`, `{{approval_status}}` |

---

## Attachments

- **Same file for everyone** — open the saved template and upload the file on its **Documents** tab; it is attached to every email the template sends.
- **Per-recipient files** — type document names in **Attachment names** (comma-separated; `*` as a wildcard; wrap a name containing a comma in double quotes). They are looked up on the record the email is about: the KYC, commitment, remittance, distribution payment, opportunity, sale, offer or interest, approval response or deal investor. A payment-received email and a document email have no such documents, so **Attachment names** adds nothing there.
- **Only attach the latest match** (on by default) attaches just the newest matching document; off attaches every match. Generated documents that are not yet approved are never attached.
- **Attachment mandatory** skips a recipient whose named document is missing; about five minutes later the person who triggered the send (or the company admins) gets one email listing the skipped recipients. Off, the email goes without that file.
- Built-in attachments stay: call notices, call reminders and distribution emails always attach the approved notice, and a document email always attaches the document.

The fund-guide walkthrough in [Fund & Commitment Notifications](fund_commitment_notifications_user_guide) has worked examples of wildcard matching.

---

## Which Notification Is Used

When an email is about to go out, CapHive looks for a template in this order:

1. **A template named by the button you clicked** — **Send Reminder <tag>**, **Send KYC Reminder (<tag>)**, **Send <subject>** on a document or opportunity, **Email Using Template:**, a sale's ad-hoc item or a fund's **Send Notification**. For KYC, document and opportunity emails it must still be enabled, otherwise the standard email is sent.
2. **Otherwise, the owner's template for that email** — the most recently created *enabled* template for that **For Notification** on the owner (your company, the sale or the approval). For deal stage emails, a template tagged with the step title wins over an untagged one.
3. **Calls and distributions** check the call or distribution first, then the fund's default (**New Call Notification** / **New Distribution Notification** on the fund).
4. **No template** — the standard CapHive email.

The **Latest** column marks the newest template for that email on the owner. Saving a new template marks older ones for the same email and owner as not latest.

---

## Previewing and Testing

- **Preview** on a template's own page renders it against the first matching record: the first KYC (KYC templates), the first remittance or payment (call templates), the first distribution payment, the fund's first commitment or KYC (fund templates) or the first approval response. Document, opportunity, deal and secondary sale templates have no **Preview** button.
- **Record-level previews:** a KYC's **Preview Notifications** menu; **Preview Notification**, **Preview Reminder** and **Preview Payment Notification** in a remittance's actions; **Preview Notification** on a distribution payment; **Actions → Preview Adhoc Fund Notification** on a commitment.
- A preview needs an approved stakeholder user on that record; otherwise it says "No approved investor access found for this user".
- To test a real send safely, send to one record (one commitment, one KYC or a narrow filter), or ask for sandbox mode, which redirects all your company's emails to the sandbox addresses.

---

## Editing, Disabling, Deleting and Restoring

- **Edit** — open the template and click **Edit**. Changes apply to the next email; emails already sent are unchanged. Only the latest template for an email can be edited, except KYC templates, document templates, **Adhoc kyc notification** and secondary sale **Adhoc notification**, which stay editable. **Dynamic Template** ones can only be edited by CapHive support.
- **Disable** — edit and switch off **Template enabled**. The standard email is used again and the template's send items disappear from document and opportunity menus.
- **Delete** — open it and click **Delete**, then confirm. Deleted templates are listed on [deleted custom notifications](/custom_notifications/show_deleted), where **Restore** brings one back.
- **Permissions** — creating, editing and deleting company-wide templates (KYC, agreement/document, opportunity) need the Company Admin role. Fund, call, distribution, deal, sale and approval templates also accept an employee with create access on that fund, deal, sale or approval.

---

## Frequently Asked Questions

### Navigation and getting there

**Where do I see all custom notifications (email templates)?**
Profile menu → **My Inbox** → **Custom Notifications** lists every custom notification in your company with its email, subject, WhatsApp text, type and owner, **Enabled** and **Latest**, plus a **Filter** panel. For KYC templates only, use [**Funds → KYCs**](/investor_kycs) → **New KYC** → **View All Custom Notifications**. These full lists open for Company Admins. See [Seeing All Custom Notifications](#seeing-all-custom-notifications).

**Where do I create a custom notification?**
From the screen it belongs to: **New KYC** on [**Funds → KYCs**](/investor_kycs) for KYC and agreement templates, the fund's **Notifications** tab for fund, call and distribution defaults, a call's or distribution's **Notification** tab, a deal's **Custom Notifications** tab, a sale's or approval's **Notification** tab, or an opportunity's **Notifications** tab. See [All Kinds of Custom Notification](#all-kinds-of-custom-notification).

**Where are Custom KYC Notification and Custom Agreement Notification?**
Sidebar → [**Funds → KYCs**](/investor_kycs) → click **New KYC**. Below **Report** the dropdown has **View All Custom Notifications**, **Custom KYC Notification** and **Custom Agreement Notification**. The dropdown is shown to employees who can create KYCs; saving these company-wide templates needs the Company Admin role.

**Where do I find a fund's, call's or distribution's notification templates?**
Open the fund → **Notifications** tab for the fund's ad-hoc templates and its call and distribution defaults. Open a call or distribution → **Notification** tab for templates that apply only to that record. See [Call and Distribution Notifications](#call-and-distribution-notifications).

**Where do I find the notification templates for a deal, secondary sale, approval or investment opportunity?**
Deal → **Custom Notifications** tab; secondary sale → **Notification** tab; approval → **Notification** tab (for users who can update it); investment opportunity → **Notifications** tab, which shows the company-wide opportunity templates. Each tab has **New Notification** → **New Custom Notification**.

**Why do I get an access error on the Notifications tab or the Custom Notifications list?**
The full lists opened from **My Inbox** → **Custom Notifications**, **View All Custom Notifications**, a fund's **Notifications** tab and a deal's **Custom Notifications** tab open for Company Admins only. Ask a company admin to manage these templates, or open the call, distribution, sale, approval or opportunity tab, which shows its templates directly.

### Creating, updating and managing custom notifications

**How do I set up a custom KYC notification?**
Go to [**Funds → KYCs**](/investor_kycs) → **New KYC** → **Custom KYC Notification**. In **For Notification** choose the KYC email to replace (**Notify kyc required**, **Kyc required reminder**, **Notify updates requested**, **Notify kyc updated** or **Notify kyc submitted**), add a **Tag** if you keep several, write the **Subject** and **Body** with placeholders, keep **Template enabled** on and **Save**. It applies to KYCs across your company. See [Custom KYC Notification](#custom-kyc-notification).

**How do I set up a custom KYC reminder email template with a tag?**
Create a **Custom KYC Notification** with **For Notification** = **Kyc required reminder** and a **Tag** such as `SEBI`. Filter the KYC list and **Bulk Actions** then shows **Send Reminder SEBI**; on a KYC, **KYC Actions** shows **Send KYC Reminder (SEBI)**. Create one tagged template per reminder wording you need.

**How do I set up a custom agreement notification?**
Go to [**Funds → KYCs**](/investor_kycs) → **New KYC** → **Custom Agreement Notification** (or **My Inbox** → **Custom Notifications** → **New Notification** → **Document Notification**). **For Notification** is **Send document**; write the subject and body, keep **Template enabled** on and save. Then send a document with **Send Document → Send <subject>** on its page, or many at once with **Email Using Template:** on a filtered documents list.

**How do I create a custom email template for capital call notices?**
Fund → **Notifications** tab → **New Notification** → **New Call Notification** for a default used by every call in the fund, or the call's **Notification** tab → **New Notification** → **New Call Notification** for that call only. Choose **Notify capital remittance** (notice), **Reminder capital remittance** or **Notify capital remittance payment**, write the text and save. See [Capital Calls](capital_calls_user_guide).

**How do I create a custom email template for distribution payment emails?**
Fund → **Notifications** tab → **New Notification** → **New Distribution Notification** for a fund-wide default, or the distribution's **Notification** tab → **New Notification** → **New Distribution Notification** for that distribution only. **For Notification** is **Send notification**. See [Capital Distributions](capital_distributions_user_guide).

**How do I create a custom document notification template?**
Profile menu → **My Inbox** → **Custom Notifications** → **New Notification** → **Document Notification**, or **New KYC** → **Custom Agreement Notification** on the KYCs list — both create the same company-wide **Send document** template. Enabled templates appear in every document's **Send Document** menu and under **Email Using Template:** on filtered document lists.

**How do I customise the deal stage-change email?**
Open the deal → **Custom Notifications** tab → **New Notification** → **New Custom Notification**, choose **Deal activity move**, and optionally set **Tag** to a step's exact title so the template is used only for that step. It is used when an investor moves to a step that notifies employees or the investor. See [Deal Notifications](#deal-notifications).

**How do I create a notification template for an investment opportunity?**
Open any opportunity → **Notifications** tab → **New Notification** → **New Custom Notification**, choose **Notify open for interests** or **Notify allocation**, write the text and save. It is shared by all your opportunities: it replaces that standard email and adds a **Send <subject>** item to every opportunity's **Notifications** menu.

**How do I send an ad-hoc custom email to secondary sale buyers or sellers?**
Open the sale → **Notification** tab → **New Notification** → **New Custom Notification**, set **For Notification** to **Adhoc notification**, choose **To** (**All Sellers**, **Verified Sellers**, **Approved Sellers**, **All Buyers** or **Shortlisted Buyers**) and save. Then pick the template by its subject in the sale's **Notifications** menu and confirm.

**How do I use placeholders in a custom notification?**
In the **Body**, choose a token from **+ Insert placeholder…**, for example `{{investor_name}}` or `{{due_date}}`; it is replaced with each recipient's value when the email is sent. The list depends on **For Notification**, placeholders do not work in the **Subject**, and a mistyped token is sent as typed. See [Placeholders (Variables)](#placeholders-variables).

**How do I attach documents to a custom notification?**
Upload a file on the saved template's **Documents** tab to send it to everyone, or type document names in **Attachment names** to attach each recipient's own document (for example `Statement of Account` or `SOA_*_2026`). Use **Only attach the latest match** and **Attachment mandatory** to fine-tune. See [Attachments](#attachments).

**How do I edit a custom notification?**
Open it and click **Edit**; the next email uses the new text. Only the latest template for an email can be edited, except KYC, document, **Adhoc kyc notification** and sale **Adhoc notification** templates. If **Edit** is missing, create a new template for that email, which becomes the latest. **Dynamic Template** ones are edited by CapHive support.

**How do I stop using a custom notification without deleting it?**
Edit it and switch off **Template enabled**, then save. The standard email is sent again (or an older enabled template for the same email, if one exists), and its **Send …** items disappear from document and opportunity menus.

**How do I delete or restore a custom notification?**
Open it, click **Delete** and confirm. Emails already sent are not affected. To bring it back, open [deleted custom notifications](/custom_notifications/show_deleted) and click **Restore** on it.

**Who can create custom notifications?**
Company Admins can create every kind. For fund, call, distribution, deal, secondary sale and approval templates, an employee with create access on that fund, deal, sale or approval can too. Company-wide KYC, agreement/document and opportunity templates need the Company Admin role. The **Dynamic Template** switch is CapHive support only.

### Why use custom notifications

**Why use a custom notification instead of the standard email?**
To send your own wording, branding and instructions, personalised with placeholders, with the right documents attached automatically, and optionally a WhatsApp message — without changing any code. The standard text stays in place for every email you have not customised.

**What is the difference between a custom KYC notification and a fund Adhoc kyc notification?**
A **Custom KYC Notification** is company-wide and changes the wording of the automatic KYC emails (KYC required, reminders, updates requested, KYC updated or submitted). A fund's **Adhoc kyc notification** is a one-off message you write on a fund and send yourself with **Send Notification** to the investor KYCs linked to that fund. See [Fund & Commitment Notifications](fund_commitment_notifications_user_guide).

**What is the difference between a fund-level call notification and a call-level one?**
A **New Call Notification** created on the fund's **Notifications** tab is the default for every call in that fund. One created on a call's **Notification** tab applies only to that call and wins over the fund default for the same email. Distributions work the same way.

**Why keep several templates for the same email?**
For KYC reminders you can offer different wording per investor group, each with its own **Send Reminder <tag>** item. For documents and opportunities, each enabled template is a separate **Send …** choice. For deals, one template per step title. Elsewhere only the newest enabled template for an email is used.

### What happens when I …

**What happens when I save a custom notification?**
The template is stored on its owner (your company, fund, call, distribution, deal, sale or approval) and nothing is sent. Older templates for the same email and owner are marked not latest. From then on, matching emails use it while it is enabled, and send items for it appear where that kind offers them.

**Which custom notification is used when several exist?**
A template picked by the button you click is used (KYC, document and opportunity templates only if still enabled). Otherwise the most recently created enabled template for that email on the owner is used; for calls and distributions the call's or distribution's own template beats the fund default, and for deals a template tagged with the step title beats an untagged one. With none, the standard email goes out. See [Which Notification Is Used](#which-notification-is-used).

**What happens when I use Bulk Actions → Send Reminder <tag> on the KYCs list?**
Each matching KYC that is not **Completed** or **Verified** gets the reminder email written in that tagged **Kyc required reminder** template, with a fresh 30-day link, sent to the stakeholder's approved users; its status becomes **Link Sent**. If the template has been disabled, the standard reminder wording is used. See [Investor KYC](investor_kyc_user_guide).

**What happens when I send a document with a custom agreement notification?**
Every user with access to the document gets the template's subject and body with the document attached (plus any files on the template's **Documents** tab), and an in-app notification is recorded. Unapproved generated documents and documents nobody has access to are not sent and show an error.

**What happens when a custom notification's body is empty?**
No email is sent for that template at all; it does not fall back to the standard text. A blank WhatsApp field likewise means no WhatsApp message.

**What happens when Attachment mandatory is on and a recipient's document is missing?**
That recipient's email is not sent and is marked skipped. About five minutes later the person who triggered the send (or the company admins) gets one email listing the skipped recipients with a **View skipped notifications** link. Other recipients get their emails normally.

**What happens when I disable or delete a custom notification?**
Emails already sent are unaffected. Future emails of that type use the next enabled template for the same email or the standard text, and the template's send items disappear from document and opportunity menus. A deleted template can be restored from [deleted custom notifications](/custom_notifications/show_deleted).

**Does creating a custom notification send anything to investors?**
No. Saving only stores the template. Emails go out when the underlying event happens (a KYC link, a call notice, a stage move) or when you click a send action such as **Send Notification**, **Send Reminder <tag>** or **Send <subject>**.

### Troubleshooting and edge cases

**My custom notification is not used and investors got the standard email — why?**
Check that **Template enabled** is on, that **For Notification** is the email that was actually sent, and that it belongs to the right owner (a call template on another call, or a KYC template when the email was a fund ad-hoc send, is not used). If an older template and a newer disabled one exist, the older enabled one is used. For deals, check the **Tag** matches the step title exactly.

**Why don't I see Send Reminder <tag> in the KYC Bulk Actions?**
Bulk actions only appear on a filtered KYC list, and tagged items appear only for **Custom KYC Notification** templates whose **For Notification** is **Kyc required reminder**. With no such template you see the plain **Send Reminder**. The label shows the template's **Tag**, so give each template a tag.

**Why is my document template missing from the Send Document menu?**
Only enabled templates of type **Send document** (created as **Custom Agreement Notification** or **Document Notification**) are listed. Check **Template enabled** on the template. On the documents list the **Email Using Template:** items appear only after a filter is applied.

**Why is there no Edit button on my custom notification?**
Only the latest template for an email can be edited, except KYC, document, **Adhoc kyc notification** and sale **Adhoc notification** templates. **Dynamic Template** ones are editable only by CapHive support, and you need create access. To change an older template, create a new one for the same email.

**Why does Preview say "No approved investor access found for this user"?**
Preview renders the email for the first matching record, and that record's stakeholder has no approved user to address it to. Approve a stakeholder user, or preview from a record whose stakeholder has one, such as a specific KYC's **Preview Notifications** menu.

**Why is there no Preview button on my document, deal, opportunity or secondary sale template?**
Those kinds have no preview. Send to a single document, investor or narrow filter first, or ask CapHive support to put your company in sandbox mode so test emails go to the sandbox addresses.

**I see Send Notification on a fund's call or distribution default template — should I use it?**
No. **Send Notification** is for **Adhoc fund notification** and **Adhoc kyc notification** templates. Call and distribution defaults are sent by the call's and distribution's own send actions (see [Capital Calls](capital_calls_user_guide) and [Capital Distributions](capital_distributions_user_guide)).

**My secondary sale ad-hoc notification sent nothing — why?**
An **Adhoc notification** only emails the group chosen in **To**; with **To** left blank nobody is emailed. Also check that the group has members (for example **Shortlisted Buyers** needs shortlisted interests) and that their users are approved.

**Why did no one get an email from my approval or deal template?**
The template only changes wording; the email must still be triggered. Approval emails go out on activation, reminder or response; deal stage emails need the deal's notifications on and the step set to notify employees or the investor. A deal template set to **Adhoc notification** is never sent — use **Deal activity move**.

**Do placeholders work in the subject line?**
No. Only the **Body** replaces placeholders; the **Subject** is sent exactly as typed. Keep personalised details such as the investor's name in the body.

---

## Related Guides

- [Investor KYC](investor_kyc_user_guide) — the **New KYC** dropdown, KYC emails and the **Send Reminder** bulk actions that use KYC templates.
- [Fund & Commitment Notifications](fund_commitment_notifications_user_guide) — sending fund ad-hoc notifications per commitment or per investor KYC.
- [Capital Calls](capital_calls_user_guide) — when call notices, reminders and payment emails are sent.
- [Capital Distributions](capital_distributions_user_guide) — when distribution payment emails are sent.
- [Document Management](document_management_user_guide) — **Send Document** and **Email Using Template:** bulk emails.
- [Investment Opportunities](investment_opportunity_user_guide) — the opportunity **Notifications** menu.
- [Deals Management](deals_management_user_guide) — deal steps that notify employees and investors.
- [Secondary Sales](secondary_sales_user_guide) — sale emails and ad-hoc messages to buyers and sellers.
