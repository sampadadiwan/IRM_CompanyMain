# CapHive Gmail Add-on

## User Setup Guide

This guide explains how to install and use the **CapHive Gmail Add-on**, which lets you file
investor emails into CapHive without leaving Gmail.

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

Filed emails appear in CapHive on the investor's record, under their communications.

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

**I filed it against the wrong record.** Click **Undo** straight away. If you have moved on, the
filing can be removed from the investor's record in CapHive.

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
