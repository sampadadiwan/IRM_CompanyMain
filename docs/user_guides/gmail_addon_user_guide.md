# CapHive Gmail Add-on

## User Setup Guide

This guide explains how to install and use the **CapHive Gmail Add-on**, which lets you file
investor emails into CapHive without leaving Gmail.

> **Where to find it:** In Gmail on a desktop browser, the orange CapHive hexagon in the right-hand side panel opens the **CapHive Filing** panel (after your administrator shares the add-on and you install it). Filed emails appear in CapHive under Sidebar → [**Stakeholders → View Stakeholders**](/investors) → open the stakeholder → **Misc → Emails** (company admins also get an **Emails** tab). You need a CapHive login and access to the stakeholder you file against.

Once installed, you can file an email against the right investor in two clicks, and everyone on
your team can see it.

> **Availability:** the add-on is **not published to the Google Workspace Marketplace**.
> Searching there will not find it, and your administrator cannot add it to your domain's app
> list yet. Until it is listed, your CapHive administrator gives you access individually —
> see section 3.

---

# 1. What the Add-on Does

- Files emails from Gmail straight into CapHive
- Suggests the right investor based on who sent the email
- Files any attachments along with the email
- Tells you when an email has already been filed, so nothing is recorded twice
- Keeps investor correspondence in one place, visible to your whole team

Your organisation's name appears in the add-on, so if you use CapHive under a different brand,
expect to see that name. Test environments add a suffix — **CapHive Filing (Staging)** — so
you can tell at a glance which system you are filing into.

---

# 2. Requirements

- A **CapHive account** — the same login you use for CapHive every day
- A **Gmail or Google Workspace account**
- Gmail in a **desktop browser**. The add-on does not appear in the Gmail mobile app.

---

# 3. Getting Access

Because the add-on is not yet listed publicly, your administrator gives you access to it
directly. There are two steps, and the second one is yours.

### Step 1 — Your administrator shares it with you

They add your Google account to the CapHive add-on project and send you a link.

### Step 2 — You install it

1. Open the link your administrator sent
2. Choose **Deploy → Test deployments**
3. Click **Install**
4. Return to Gmail and reload the page

> Being given the link is not the same as installing. Until you complete step 2 the add-on
> will not appear in Gmail, even though you can open the link.

**You will see a warning that Google has not verified the app.** This is expected — it appears
for any add-on that is not yet published, and will go away once CapHive completes Google's
review. Choose **Advanced**, then continue.

The add-on asks for three permissions: to read **the message you currently have open** (not your
mailbox), to run the add-on, and to contact CapHive. Nothing broader is requested.

---

# 4. Finding the Add-on

Gmail add-ons do not have a toolbar button. They appear as an **icon in the right-hand side
panel** — the narrow vertical strip on the far right that also holds Calendar, Keep, Tasks and
Contacts. Installed add-ons sit below those, under a dividing line.

Look for the **orange CapHive hexagon**. Clicking it opens the CapHive panel.

**If you cannot see the side panel at all:**

- **Reset your browser zoom** with Ctrl+0 (Cmd+0) and maximise the window. Gmail hides the whole
  side panel when the window is too narrow, and zoom counts toward that. This is the most common
  cause.
- **Look for the small arrow in the very bottom-right corner** of the Gmail window. It collapses
  and expands the panel, and the setting sticks. There is no equivalent option in Gmail Settings.
- If you are on a **company Google account** and the panel is present but shows no add-ons at
  all, your IT administrator may have blocked third-party add-ons.

**If the side panel is there but the CapHive icon is not**, reload Gmail with Ctrl+Shift+R
(Cmd+Shift+R). If it is still missing, you have probably not completed step 2 in section 3.

---

# 5. Signing In

The first time you open the panel it asks you to sign in.

Click **Sign in to CapHive**. A browser tab opens on your normal CapHive sign-in page, and you
log in exactly as you usually do — including single sign-on or multi-factor authentication if
your organisation uses them. Close the tab afterwards and return to Gmail.

> **You will never be asked to type your CapHive password into the Gmail panel itself.** If
> anything inside the panel ever asks for your password, do not enter it, and tell your
> administrator.

Your sign-in is remembered for about a month. After that, or if your CapHive access changes, the
panel shows **Sign in to CapHive** again.

---

# 6. Filing an Email

### Step 1 — Open the email and the panel

Open the email, then click the CapHive icon in the side panel. It checks the email straight away.

### Step 2 — Check the suggested record

The add-on suggests an investor based on **who sent the email**, and tells you why it chose them:

| What you see | What it means |
| --- | --- |
| Matched on a known investor contact | The sender is a recognised contact on that investor's record |
| Matched on the investor's primary email | The sender is the investor's main email address |
| Matched on email domain | The sender works at the same organisation as that investor |

Always check the suggestion before filing. It is a suggestion, not a decision.

If more than one investor matches — for example an adviser who acts for several — you are shown
all of them and choose. The add-on never guesses between them.

### Step 3 — Change the record if needed

If the suggestion is wrong, or nothing was suggested, type a name into **Search records** and
click **Search**. Pick the right one from the list, then click **File to selected record**.

### Step 4 — File it

Click **File to CapHive**. The panel confirms, and offers:

- **View in CapHive** — opens the filed email in CapHive
- **Undo** — removes the filing again, if you filed it against the wrong record

---

# 7. When Nothing Is Suggested

This is normal and does not mean anything is wrong. The add-on only suggests a record based on
the **sender**, so it will not suggest one when:

- **You sent the email.** Emails you sent to an investor show no suggestion, because the sender
  is you. Search for the investor and file it.
- The sender is not recorded against any investor in CapHive
- The email is internal, or from someone unrelated

In every case you can still file it — search, select, and file.

This is deliberate. The add-on would rather offer nothing than confidently suggest the wrong
investor.

---

# 8. What Gets Stored

- The subject and full message, with its formatting intact
- Who it was from, and who it was sent to
- Any attachments
- The date it was sent
- Who filed it, and when
- The investor it was filed against

Filed emails appear in CapHive on the investor's stakeholder page, under **Misc → Emails**.

---

# 9. Filing the Same Email Twice

If an email has already been filed, the panel tells you so, and shows who filed it and against
which record. It will not be recorded twice.

You can still file it against a *different* investor if the email genuinely relates to more than
one.

This works across the whole team, and across Gmail and Outlook: if a colleague filed the email
from Outlook, you will see that here.

---

# 10. For Administrators

The add-on cannot yet be added to your domain's Google Workspace app list, because it is not
published to the Marketplace. Publishing requires Google's OAuth verification review, which
CapHive is working through.

Until then, giving someone access means adding their Google account to the CapHive add-on
project and sending them the link, then asking them to complete section 3, step 2 themselves.
This works for a handful of users; it does not scale to a whole firm, which is what the
Marketplace listing will solve.

Two things to tell users in advance, because both look alarming and neither is a problem:

- The **unverified app** warning during installation
- The fact that **being sent the link does not install anything** — they must install the test
  deployment themselves

If your organisation restricts third-party Google apps, you may also need to allow this one
before your users can complete installation.

---

# 11. Troubleshooting

**I cannot see the side panel.** See section 4 — almost always browser zoom, window width, or
the collapse arrow in the bottom-right corner.

**The side panel is there but CapHive is not.** Reload Gmail with Ctrl+Shift+R. If still absent,
confirm you completed the install step yourself, and that you are looking at the same Google
account you installed it under — check the account switcher, since add-ons install per account.

**It keeps asking me to sign in.** Your session has expired, which happens about once a month.
Sign in again. If it happens repeatedly within a day, tell your administrator.

**The wrong investor was suggested.** Search and pick the right one before filing. If a
particular sender is consistently matched to the wrong investor, ask your administrator to check
that investor's email address in CapHive.

**I filed it against the wrong record.** Click **Undo** straight away. If you have moved on, open the
investor's stakeholder page in CapHive, go to **Misc → Emails**, open the filed email and click **Delete**.

**The panel shows an error.** Note the exact wording and send it to your administrator —
error messages here identify the cause precisely, and a screenshot of the message is far more
useful than a description of it.

---

# 12. Security and Privacy

- You sign in through your organisation's normal CapHive login, including single sign-on and
  multi-factor authentication
- Your password is never entered into, or seen by, the Gmail panel
- The add-on can only read **the message you have open**. It has no access to the rest of your
  mailbox, your other messages, or your contacts.
- You can only file against investors you already have permission to see in CapHive
- Nothing is filed until you confirm it

---

# 13. Best Practice

- File investor emails as you read them, so the record stays current
- Check the suggested investor before confirming
- Do not file internal-only emails
- If an email covers two investors, file it against both

---

# 14. Support

If you have trouble installing or using the add-on, contact **support@caphive.com** and include:

- Whether you use a personal Gmail account or a company Google account
- A screenshot of the panel, including any error message
- The subject of the email you were trying to file

---

# 15. Frequently Asked Questions

## Navigation and getting there

**Where do I find the CapHive add-on in Gmail?**
Open Gmail in a desktop browser and look in the right-hand side panel, below Calendar, Keep, Tasks and Contacts, for the orange CapHive hexagon. Click it to open the **CapHive Filing** panel. See [section 4](#4-finding-the-add-on).

**How do I get the add-on in the first place?**
Ask your CapHive administrator to share it with your Google account; they send you a link. Open it, choose **Deploy → Test deployments**, click **Install**, then reload Gmail. See [section 3](#3-getting-access).

**Where do filed emails show up in CapHive?**
On the stakeholder (investor) they were filed against: Sidebar → [**Stakeholders → View Stakeholders**](/investors), open the stakeholder, then **Misc → Emails** (company admins also see an **Emails** tab). **View in CapHive** in the panel opens the single filed email in CapHive.

**Where do the attachments of a filed email go?**
They are saved as CapHive documents on the filed email, in the stakeholder's document folder under **Incoming Emails** and then a sub-folder named after the sender.

**Is there a page listing every filed email for my organisation?**
There is no menu link for it, but you can open the [filed emails list](/incoming_emails) directly to list your organisation's filed emails. Day to day, use **Misc → Emails** on each stakeholder's page.

## Installing, filing and managing filings

**How do I sign the add-on in to CapHive?**
Open the panel and click **Sign in to CapHive**. A browser tab opens on the normal CapHive sign-in page; log in as usual, including two-factor authentication, close the tab and return to Gmail. See [section 5](#5-signing-in).

**How do I file an email?**
Open the email, click the CapHive icon, check the suggested stakeholder and click **File to CapHive**. See [section 6](#6-filing-an-email).

**How do I file an email against a different stakeholder than the one suggested?**
Type part of the name into **Search records**, click **Search**, choose the right record and click **File to selected record**. The search shows up to 25 matching stakeholders you can see.

**How do I file one email against two stakeholders?**
File it against the first, then search for the second and file again. The add-on only blocks a repeat filing against the same stakeholder, not a filing against a different one. See [section 9](#9-filing-the-same-email-twice).

**How do I undo a filing?**
Click **Undo** on the confirmation straight after filing; the panel shows "Filing removed.". Later on, open the filed email in CapHive from the stakeholder's **Misc → Emails** list and click **Delete**.

**What permission do I need to file emails?**
A CapHive login in your organisation and permission to see the stakeholder you file against; the search only lists stakeholders you can already open. Installing the add-on itself needs your administrator to share it with your Google account.

**Can I file emails against a fund, deal or portfolio company record?**
No. The add-on files against stakeholder (investor) records only, so use the stakeholder the correspondence belongs to.

**How does an administrator roll the add-on out to more people?**
For now, each person's Google account is added to the CapHive add-on project and sent the link, and each person installs it themselves. See [section 10](#10-for-administrators).

## Why use the Gmail add-on

**Why should I file investor emails into CapHive?**
Correspondence stops living in one person's inbox: the whole team sees it on the stakeholder's record, alongside commitments, KYC and documents. It survives staff changes and gives you a history when an investor asks what was agreed.

**What does the add-on save me compared with doing it by hand?**
You do not download attachments, find the stakeholder and upload them separately. The add-on suggests the stakeholder from the sender, files the message and attachments in one click, and warns you if the email is already filed.

**Who typically uses the add-on?**
Investor relations, fundraising and fund operations staff who correspond with LPs and their advisers from Gmail or Google Workspace.

**What happens if we don't file emails?**
Nothing breaks, but colleagues cannot see what was said to an investor, and the history leaves with whoever holds the inbox. If only some teammates file their emails, the record is incomplete.

## What happens when I…

**What happens when I click File to CapHive?**
CapHive saves the email, sender, recipients, date and attachments against that stakeholder, recording you as the filer and the time. It appears under the stakeholder's **Misc → Emails** for everyone who can see that stakeholder; no one is notified and the investor is not contacted.

**What happens if the email was already filed against that stakeholder?**
Nothing new is saved. The panel shows it as already filed, with who filed it and against which record, whether it was filed from Gmail or Outlook, and no **Undo** is offered.

**What happens when I click Undo?**
The filing and its attachments are removed from CapHive and the panel shows "Filing removed.". Attachments of other emails filed from the same sender stay in place, and the email in Gmail is untouched.

**What happens in Gmail when I file an email?**
Nothing changes in your mailbox: no label is added and the message is not moved. The add-on only reads the message you have open.

**What happens when I sign in?**
CapHive gives the add-on a sign-in token tied to your own CapHive user, valid for 30 days. When it expires or your CapHive access changes, the panel shows **Sign in to CapHive** again.

**What happens if the sender matches more than one stakeholder?**
The panel lists every match and you choose; it never picks between them for you. See [section 6](#6-filing-an-email).

## Troubleshooting and edge cases

**Does the add-on work in the Gmail mobile app?**
No. It only appears in Gmail in a desktop browser.

**Can I file an email I sent myself?**
Yes. No stakeholder is suggested because the sender is you, so search for the stakeholder and click **File to selected record**. See [section 7](#7-when-nothing-is-suggested).

**Does filing notify the investor or my colleagues?**
No. Filing only records the email in CapHive; colleagues see it when they open **Misc → Emails** on the stakeholder's page.

**I installed the add-on but my colleague cannot see it.**
Add-ons install per Google account. Your colleague needs their own invitation from the administrator and must complete the install step themselves.

**The search does not find a stakeholder I know exists.**
Search matches stakeholder names, not email addresses, and only returns stakeholders you have access to. Try part of the name, and ask your CapHive administrator if you should have access to that stakeholder.

For other problems, see [section 11](#11-troubleshooting).

---

# 16. Related Guides

- [Outlook Setup](outlook_setup_user_guide) — the same filing from Outlook; duplicates are detected across both.
- [Stakeholders (Investors)](investors_user_guide) — the stakeholder records emails are filed against.
- [LP CRM](lp_crm_user_guide) — notes and touch points that sit alongside filed correspondence.
- [Document Management](document_management_user_guide) — where filed attachments live as documents.
- [Two-Factor Authentication](two_factor_authentication_user_guide) — the sign-in step you complete when connecting the add-on.
