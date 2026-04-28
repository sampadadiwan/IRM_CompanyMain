
# CapHive Outlook Add-in

## User Setup Guide

This guide explains how to install and use the **CapHive Outlook Add-in**, which allows you to **file investor emails directly into CapHive**.

Once installed, you can file any email under the appropriate investor in just a few clicks.

---

# 1. What the Add-in Does

The CapHive Outlook Add-in allows you to:

• File emails from Outlook directly into CapHive
• Automatically match investors based on email address
• Maintain a central investor communication history
• Ensure important communication is recorded and visible to your team

---

# 2. Requirements

Before installing the add-in, ensure you have:

• A **CapHive user account**
• Access to **Microsoft Outlook (Web or Desktop)**
• The **CapHive Add-in manifest file** provided by your administrator

You will also need your **CapHive login credentials**.

---

# 3. Installing the Add-in in Outlook Web

### Step 1 — Open Outlook

Go to:

```
https://outlook.office.com
```

Sign in with your Microsoft account.

---

### Step 2 — Open Add-ins

Click the **Settings icon (⚙️)** in the top right.

Then click:

```
View all Outlook settings
```

---

### Step 3 — Open Add-in Management

Navigate to:

```
Mail → Customize actions
```

Scroll to the **Add-ins** section and click:

```
Manage add-ins
```

---

### Step 4 — Upload the CapHive Add-in

Click:

```
Add from file
```

Upload the provided file:

```
caphive_outlook_addin.xml
```

Confirm the installation.

---

# 4. Verifying Installation

Open any email in Outlook.

You should now see a new button in the email toolbar:

```
File to CapHive
```

Clicking this button opens the **CapHive panel**.

---

# 5. First-Time Login

When you open the add-in for the first time, you will be asked to log in to CapHive.

Enter your CapHive credentials.

```
Email
Password
```

You will be redirected to the CapHive add-in panel after login.

---

# 6. Filing an Email

### Step 1 — Open an Email

Open an email from an investor.

Example:

```
From: investor@abcfo.com
Subject: Capital call question
```

---

### Step 2 — Click “File to CapHive”

Click the button:

```
File to CapHive
```

The CapHive panel opens on the right side.

---

### Step 3 — Investor Matching

The system automatically tries to match the email to an investor.

Matching is based on the investor email address stored in CapHive.

Possible outcomes:

| Result             | Description                     |
| ------------------ | ------------------------------- |
| Investor found     | Investor detected automatically |
| Multiple investors | You must select the correct one |
| No match           | You can search for the investor |

---

### Step 4 — Confirm Filing

Once the correct investor is selected, click:

```
Confirm Filing
```

The email will now be stored in CapHive.

---

# 7. What Gets Stored in CapHive

The following information is saved:

• Email subject
• Sender email
• Recipients (To / CC)
• Email body
• Timestamp
• Associated investor

This information is stored in CapHive under the investor's communication record.

---

# 8. Viewing Filed Emails in CapHive

Once filed, emails will appear in:

```
Investor → Communications → Emails
```

Team members with permission can view the stored communication.

---

# 9. Duplicate Protection

If an email has already been filed, CapHive will detect this and notify you.

Duplicate emails will not be stored again.

---

# 10. Troubleshooting

### The "File to CapHive" button does not appear

Try the following:

• Refresh Outlook
• Ensure the add-in is installed under **Manage Add-ins**
• Reinstall the manifest file

---

### Login keeps redirecting to sign-in

Make sure cookies are enabled for the CapHive domain.

---

### Investor was not matched

You can manually search and select the correct investor.

---

# 11. Security

The add-in uses your existing **CapHive login session**.

• No email data is stored outside CapHive
• Only authorized users can file emails
• Permissions are enforced based on investor access

---

# 12. Support

If you encounter any issues installing or using the add-in, contact:

```
support@caphive.com
```

Include:

• Your Outlook version
• A screenshot of the issue
• The email you attempted to file (if applicable)

---

# 13. Best Practices

To keep investor communication well organized:

• File important investor emails promptly
• Verify the investor match before confirming
• Avoid filing internal-only emails

---

✅ **Tip:** Filing emails immediately after reading them ensures the communication is captured for your entire team.

---
