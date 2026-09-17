# CapHive Outlook Add-in

## User Setup Guide

This guide explains how to install and use the **CapHive Outlook Add-in**, which lets you file
investor emails into CapHive without leaving Outlook.

> **Where to find it:** In Outlook on the web or the Windows/Mac desktop app, open an email and click **File to CapHive** (Home ribbon or message toolbar) to open the CapHive panel, once your administrator has installed the add-in or sent you its install link. Filed emails appear in CapHive under Sidebar → [**Stakeholders → View Stakeholders**](/investors) → open the stakeholder → **Misc → Emails**. You need a CapHive login and access to the stakeholder you file against.

Once installed, you can file an email against the right investor in two clicks, and everyone on
your team can see it.

> **Availability:** the add-in is not published to the Microsoft store. Your CapHive
> administrator installs it for your organisation, or sends you a link to install it yourself.

---

# 1. What the Add-in Does

- Files emails from Outlook straight into CapHive
- Suggests the right investor based on who sent the email
- Files any attachments along with the email
- Tells you when an email has already been filed, so nothing is recorded twice
- Keeps investor correspondence in one place, visible to your whole team

---

# 2. Requirements

- A **CapHive account** — the same login you use for CapHive every day
- **Outlook on the web**, or the **desktop Outlook app for Windows or Mac**
- The **install link** from your CapHive administrator

The add-in is not available in Outlook on a phone or tablet. Everywhere else, it is the same
add-in: install it once and it follows your mailbox to every copy of Outlook you use.

Your organisation's name appears throughout the add-in, so if you use CapHive under a different
brand, expect to see that name instead of "CapHive" on the button and panel.

---

# 3. Installing the Add-in

Most organisations have this installed centrally by an administrator, in which case the add-in
simply appears in Outlook and you can skip to section 4.

> **You only ever install this once.** The add-in is attached to your mailbox, not to one copy
> of Outlook. Install it in any one place and it appears everywhere you read that mailbox —
> the desktop app on Windows, the desktop app on Mac, and Outlook on the web. There is no
> separate download to run on your computer.

### In Outlook on the web

1. Open Outlook and click the **Settings** gear in the top right
2. Search the settings for **Add-ins**, and open **Manage add-ins** (older versions:
   **Mail → Customise actions → Add-ins**)
3. Choose **My add-ins**, then **Add a custom add-in → Add from URL**
4. Paste the install link your administrator gave you, and confirm

### In the desktop app on Windows or Mac

You can do the same thing without leaving the desktop app:

1. Open any email, and click **Get Add-ins** on the **Home** ribbon (on Mac you may find it
   under **Tools → Get Add-ins**)
2. Choose **My add-ins**, then **Add a custom add-in → Add from URL**
3. Paste the install link your administrator gave you, and confirm
4. Close and reopen Outlook — the button appears on the ribbon when it starts again

If **Add a custom add-in** is missing, your version of Outlook or your organisation's settings
do not allow installing add-ins yourself. Install it from Outlook on the web instead, using the
steps above — it will then show up in the desktop app — or ask your administrator to install it
for you.

Outlook will warn you that the add-in comes from outside the store. That is expected for an
add-in your own organisation provides.

**Administrators** installing for everyone should use the Microsoft 365 admin centre instead:
**Settings → Integrated apps → Upload custom apps**, using the same link. Allow up to 24 hours
for it to reach all users. A central install reaches the desktop apps and the web in the same
way — nobody needs to install anything on their own computer.

---

# 4. Finding the Add-in

Open any email. A button appears labelled **File to CapHive** (or your organisation's name):

- **In the desktop app**, on the **Home** ribbon, in its own CapHive group
- **In Outlook on the web**, in the toolbar above the message

Clicking it opens the CapHive panel on the right-hand side.

If you do not see the button, look under the **three dots (…)** in the message toolbar — Outlook
moves buttons there when the window is narrow.

---

# 5. Signing In

The first time you open the panel it asks you to sign in.

Click **Sign in to CapHive**. A separate sign-in window opens, and you log in exactly as you
normally would — including single sign-on or multi-factor authentication if your organisation
uses them.

> **You will never be asked to type your CapHive password into the panel itself.** If anything
> inside the Outlook panel ever asks for your password, do not enter it, and tell your
> administrator.

Once signed in, the panel shows **Signed in as** your name. You stay signed in for about a month
before being asked again.

---

# 6. Filing an Email

### Step 1 — Open the email and the panel

Open the email, then click **File to CapHive**. The panel checks the email straight away.

### Step 2 — Check the suggested record

The add-in suggests an investor based on **who sent the email**, and tells you why it chose them:

| What you see | What it means |
| --- | --- |
| Matched on a known investor contact | The sender is a recognised contact on that investor's record |
| Matched on the investor's primary email | The sender is the investor's main email address |
| Matched on email domain | The sender works at the same organisation as that investor |

Always check the suggestion before filing. It is a suggestion, not a decision.

### Step 3 — Change the record if needed

If the suggestion is wrong, or nothing was suggested, click **Change record** and search by name.
Pick the right one from the list.

### Step 4 — File it

Click **File to CapHive**. The panel confirms with **Filed to CapHive**, and offers:

- **View in CapHive** — opens the filed email in CapHive
- **Undo** — removes the filing again, if you filed it against the wrong record

---

# 7. When Nothing Is Suggested

This is normal and does not mean anything is wrong. The add-in only suggests a record based on the
**sender**, so it will not suggest one when:

- **You sent the email.** Emails you sent to an investor show no suggestion, because the sender is
  you. Search for the investor and file it.
- The sender is not recorded against any investor in CapHive
- The email is internal, or from someone unrelated

In every case you can still file it — click **Change record**, search, and file.

This is deliberate. The add-in would rather offer nothing than confidently suggest the wrong
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
one — the panel offers **File again to a different record**.

This works across the whole team, and across Outlook and Gmail: if a colleague filed the email
from Gmail, you will see that here.

---

# 10. Troubleshooting

**The button does not appear.** Refresh Outlook, then check under the three dots (…) in the
message toolbar. In the desktop app, close Outlook completely and reopen it — a newly installed
add-in only appears on the ribbon after a restart, and a central install can take up to 24 hours
to reach you. If it is still missing, confirm with your administrator that the add-in is
installed for your account.

**It works in Outlook on the web but not in the desktop app.** It is the same add-in and the
same installation, so nothing needs installing again. Close the desktop app completely and
reopen it. If it is still missing after a restart, tell your administrator — some organisations
restrict which add-ins the desktop app is allowed to load.

**The panel is blank.** Close and reopen it. If it stays blank, tell your administrator which
version of Outlook you are using — the panel needs to load from CapHive, and a network or
security policy can block it.

**It keeps asking me to sign in.** Your session has expired, which happens about once a month.
Click **Sign in to CapHive** again. If it happens repeatedly within a day, tell your
administrator.

**The wrong investor was suggested.** Click **Change record** and pick the right one before
filing. If a particular sender is consistently matched to the wrong investor, ask your
administrator to check that investor's email address in CapHive.

**I filed it against the wrong record.** Click **Undo** straight away. If you have moved on,
open the investor's stakeholder page in CapHive, go to **Misc → Emails**, open the filed email and click **Delete**.

---

# 11. Security and Privacy

- You sign in through your organisation's normal CapHive login, including single sign-on and
  multi-factor authentication
- Your password is never entered into, or seen by, the Outlook panel
- The add-in only reads the email you have open — it has no access to the rest of your mailbox
- You can only file against investors you already have permission to see in CapHive
- Nothing is filed until you confirm it

---

# 12. Best Practice

- File investor emails as you read them, so the record stays current
- Check the suggested investor before confirming
- Do not file internal-only emails
- If an email covers two investors, file it against both

---

# 13. Support

If you have trouble installing or using the add-in, contact **support@caphive.com** and include:

- Which version of Outlook you use (web, Windows, or Mac)
- A screenshot of the panel
- The subject of the email you were trying to file

---

# 14. Frequently Asked Questions

## Navigation and getting there

**Where do I find the CapHive add-in in Outlook?**
Open any email and click **File to CapHive**: on the **Home** ribbon in its own **CapHive** group in the desktop app, or in the toolbar above the message in Outlook on the web. If the window is narrow, look under the three dots (…). See [section 4](#4-finding-the-add-in).

**How do I get the add-in installed?**
Either your administrator installs it centrally, or they send you an install link that you add under **My add-ins → Add a custom add-in → Add from URL**. See [section 3](#3-installing-the-add-in).

**Where do filed emails show up in CapHive?**
On the stakeholder (investor) they were filed against: Sidebar → [**Stakeholders → View Stakeholders**](/investors), open the stakeholder, then **Misc → Emails** (company admins also see an **Emails** tab). **View in CapHive** in the panel opens the filed email in CapHive.

**Where do the attachments of a filed email go?**
They are saved as CapHive documents on the filed email, in the stakeholder's document folder under **Incoming Emails** and then a sub-folder named after the sender.

**Is there a page listing every filed email for my organisation?**
There is no menu link for it, but the [filed emails list](/incoming_emails) shows all of your organisation's filed emails. Day to day, use **Misc → Emails** on each stakeholder's page.

## Installing, filing and managing filings

**How do I install the add-in myself in Outlook on the web?**
Click the **Settings** gear, search for **Add-ins** and open **Manage add-ins**, choose **My add-ins → Add a custom add-in → Add from URL**, paste your administrator's link and confirm. It then appears in the desktop app too.

**How do I install it from the desktop app?**
Open an email, click **Get Add-ins** on the **Home** ribbon (on Mac possibly **Tools → Get Add-ins**), choose **My add-ins → Add a custom add-in → Add from URL**, paste the link, confirm, and restart Outlook.

**How does an administrator install it for everyone?**
In the Microsoft 365 admin centre, go to **Settings → Integrated apps → Upload custom apps** and use the same link. Allow up to 24 hours for it to reach all users.

**How do I sign the add-in in to CapHive?**
Open the panel and click **Sign in to CapHive**. A separate window opens on the normal CapHive sign-in, including two-factor authentication; once done the panel shows **Signed in as** your name. See [section 5](#5-signing-in).

**How do I file an email?**
Open the email, click **File to CapHive**, check the record shown under **Filing against** and click **File to CapHive** in the panel. See [section 6](#6-filing-an-email).

**How do I file against a different stakeholder than the one suggested?**
Click **Change record**, type part of the name into **Search investors…** and pick the right stakeholder before filing. The list only includes stakeholders you can see in CapHive.

**How do I file one email against two stakeholders?**
File it against the first, then use **File again to a different record** and choose the second. It is only blocked from being filed twice against the same stakeholder. See [section 9](#9-filing-the-same-email-twice).

**How do I undo a filing?**
Click **Undo** straight after filing; the panel shows "Filing removed." and the **File to CapHive** button becomes available again. Later on, open the filed email in CapHive from the stakeholder's **Misc → Emails** list and click **Delete**.

**What permission do I need to file emails?**
A CapHive login in your organisation and permission to see the stakeholder you file against. Installing the add-in yourself also needs your Outlook or organisation settings to allow custom add-ins.

**Can I file emails against a fund, deal or portfolio company record?**
No. The add-in files against stakeholder (investor) records only, so use the stakeholder the correspondence belongs to.

## Why use the Outlook add-in

**Why should I file investor emails into CapHive?**
Correspondence stops living in one person's inbox: the whole team sees it on the stakeholder's record, alongside commitments, KYC and documents. It survives staff changes and gives you a history when an investor asks what was agreed.

**What does the add-in save me compared with doing it by hand?**
You do not download attachments, find the stakeholder and upload them separately. The add-in suggests the stakeholder from the sender, files the message and attachments in one click, and warns you if the email is already filed.

**Who typically uses the add-in?**
Investor relations, fundraising and fund operations staff who correspond with LPs and their advisers from Microsoft 365 or Outlook.

**What happens if we don't file emails?**
Nothing breaks, but colleagues cannot see what was said to an investor, and the history leaves with whoever holds the mailbox. If only some teammates file their emails, the record is incomplete.

## What happens when I…

**What happens when I click File to CapHive in the panel?**
CapHive saves the email, sender, recipients, date and attachments against that stakeholder, recording you as the filer and the time, and the panel shows "Filed to CapHive.". No one is notified and the investor is not contacted.

**What happens if the email was already filed against that stakeholder?**
Nothing new is saved. The panel says it is already filed, with who filed it and against which record, whether that was from Outlook or Gmail, and offers **File again to a different record**.

**What happens when I click Undo?**
The filing and its attachments are removed from CapHive and the panel shows "Filing removed.". Attachments of other emails filed from the same sender stay in place, and the email in Outlook is untouched.

**What happens in Outlook when I file an email?**
Nothing changes in your mailbox: the message is not moved or categorised. The add-in only reads the email you have open.

**What happens when I sign in?**
CapHive gives the add-in a sign-in token tied to your own CapHive user, valid for 30 days. When it expires or your CapHive access changes, the panel asks you to sign in again.

**What happens when a central install is rolled out?**
The **File to CapHive** button appears for each user within about 24 hours, in every copy of Outlook they use, with nothing to install on their computer. Each person still signs in to CapHive the first time they open the panel.

## Troubleshooting and edge cases

**Does the add-in work on my phone or tablet?**
No. It works in Outlook on the web and the desktop app for Windows or Mac only.

**Can I file an email I sent myself?**
Yes. No stakeholder is suggested because the sender is you, so click **Change record**, search and file. See [section 7](#7-when-nothing-is-suggested).

**Does filing notify the investor or my colleagues?**
No. Filing only records the email in CapHive; colleagues see it under **Misc → Emails** on the stakeholder's page.

**Add a custom add-in is missing from my Outlook. What now?**
Your Outlook version or organisation settings do not allow installing add-ins yourself. Install it from Outlook on the web instead, or ask your administrator to install it centrally.

**The search does not find a stakeholder I know exists.**
Search matches stakeholder names, not email addresses, and only returns stakeholders you have access to. Try part of the name, and ask your CapHive administrator if you should have access to that stakeholder.

For other problems, see [section 10](#10-troubleshooting).

---

# 15. Related Guides

- [Gmail Add-on](gmail_addon_user_guide) — the same filing from Gmail; duplicates are detected across both.
- [Stakeholders (Investors)](investors_user_guide) — the stakeholder records emails are filed against.
- [LP CRM](lp_crm_user_guide) — notes and touch points that sit alongside filed correspondence.
- [Document Management](document_management_user_guide) — where filed attachments live as documents.
- [Two-Factor Authentication](two_factor_authentication_user_guide) — the sign-in step you complete when connecting the add-in.
