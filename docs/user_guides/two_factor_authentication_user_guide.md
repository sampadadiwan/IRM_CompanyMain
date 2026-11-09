# Two-Factor Authentication User Guide

**Two-Factor Authentication (2FA)** adds an extra layer of security to your account. After entering your password, you will be asked for a one-time code before you are signed in. This guide covers enabling 2FA, choosing your delivery method, and logging in.

> **Where to find it:** Top-right **Profile menu** (your avatar) → **My Profile** → **Edit** → **Enable Two-Factor Authentication**; you then pick and confirm a method at your next sign-in. Anyone can do this for their own account. Turning it **off** is on **My Profile** → **Turn off 2FA** (password + current code). Resetting another user's method needs the **company_admin** role (**Reset 2FA Method** on their profile). CapHive **support** and **super** users must use 2FA from their region's enforcement date — see [Required for CapHive support and super users](#required-for-caphive-support-and-super-users).

---

## Table of Contents

1. [Overview](#overview)
2. [Enabling 2FA](#enabling-2fa)
3. [Choosing Your Verification Method](#choosing-your-verification-method)
4. [WhatsApp Mode — Setup](#whatsapp-mode-setup)
5. [Authenticator App Mode — Setup](#authenticator-app-mode-setup)
6. [Logging In with 2FA](#logging-in-with-2fa)
7. [Changing Your Verification Method](#changing-your-verification-method)
8. [Disabling 2FA](#disabling-2fa)
9. [Required for CapHive support and super users](#required-for-caphive-support-and-super-users)
10. [Frequently Asked Questions](#frequently-asked-questions)
11. [Related Guides](#related-guides)

---

## Overview

When 2FA is enabled, signing in requires two things:

1. **Something you know** — your password
2. **Something you have** — your phone (WhatsApp message, text message or authenticator app)

```mermaid
sequenceDiagram
    participant U as You
    participant S as System
    participant P as Your Phone

    U->>S: Enter email + password
    S->>S: Password correct
    S->>P: Send code (WhatsApp / SMS) or prompt app
    U->>S: Enter 6-digit code
    S->>U: Signed in
```

---

## Enabling 2FA

You can only enable or disable 2FA for your own account.

1. Go to your **Profile** page (click your avatar in the top-right corner, then **My Profile**)
2. Click **Edit**
3. Switch on **Enable Two-Factor Authentication**
4. Click **Save**

2FA does not take effect immediately. The next time you log in, you will be guided through choosing a verification method and completing setup.

---

## Choosing Your Verification Method

The first time you log in after enabling 2FA, you will see the **Set Up Two-Factor Authentication** screen. Pick an option and click **Continue**:

| Option | How it works | Best for |
|---|---|---|
| **WhatsApp** | A code is automatically sent to your WhatsApp each time you log in | Users who prefer simplicity and always have their phone |
| **Text message (SMS)** | A code is sent to your mobile number by text message each time you log in (only offered where CapHive has text messages switched on for your number) | Users without WhatsApp who still want a code sent to them |
| **Authenticator App** | You read a code from an app on your phone (works offline) | Users who want the most secure option |

> The WhatsApp and text message options only appear if your profile has a mobile number. If your profile has a number but WhatsApp is not enabled on it, the WhatsApp option is shown greyed out; switch on **Whatsapp enabled** on your profile's **Edit** page, or ask your administrator to.

```mermaid
sequenceDiagram
    participant U as You
    participant S as System

    U->>S: Log in (first time after enabling 2FA)
    S->>U: Choose your method
    alt WhatsApp selected
        S->>U: Send test code to WhatsApp
        U->>S: Enter code to confirm
        S->>U: WhatsApp mode active
    else Authenticator selected
        S->>U: Show QR code
        U->>S: Scan + enter code from app
        S->>U: Authenticator mode active
    end
```

---

## WhatsApp Mode — Setup

1. On the mode selection screen, choose **WhatsApp** and click **Continue**
2. A 6-digit code is immediately sent to your WhatsApp number (click **Didn't get it? Resend code via WhatsApp** if it does not arrive)
3. Enter the code and click **Confirm & Enable 2FA**
4. You are signed in — setup is complete

**Text message (SMS)** works the same way: choose it, click **Continue**, enter the code texted to your phone (or click **Didn't get it? Send another code**) and click **Confirm & Enable 2FA**.

No app to install. No QR code to scan. Each time you log in going forward, a code is sent to your WhatsApp automatically.

> If you lose access to your WhatsApp number, contact your administrator to reset your 2FA method.

---

## Authenticator App Mode — Setup

### Step 1: Install an Authenticator App

If you do not already have one, install any of the following on your phone:

- Google Authenticator (iOS / Android)
- Authy (iOS / Android)
- Microsoft Authenticator (iOS / Android)

### Step 2: Scan the QR Code

The setup page shows a QR code. Open your authenticator app, tap **Add** or **+**, and scan the code. A new entry will appear in the app showing a 6-digit code that refreshes every 30 seconds.

If you cannot scan, tap **Enter key manually** in your app and type the secret key shown on screen.

### Step 3: Enter the Code

Enter the 6-digit code currently shown in your app and click **Confirm & Enable 2FA**.

```mermaid
sequenceDiagram
    participant U as You
    participant A as Authenticator App
    participant S as System

    U->>A: Install app + scan QR code
    A->>U: Show 6-digit code
    U->>S: Enter code
    S->>U: Signed in
```

---

## Logging In with 2FA

### WhatsApp Mode

1. Enter your email and password
2. A code is automatically sent to your WhatsApp
3. Enter the code on the verification screen and click **Verify**
4. If you did not receive the code, click **Resend code via WhatsApp**

In **Text message (SMS)** mode the steps are the same; if the text does not arrive, click **Didn't get it? Send another code**.

### Authenticator App Mode

1. Enter your email and password
2. Open your authenticator app and read the current 6-digit code
3. Enter the code and click **Verify**

### Failed Attempts

After **3 failed attempts**, your session is reset and you must sign in again from the beginning.

Codes refresh every 30 seconds — if one fails, wait for the next one and try again. Make sure your phone's clock is set to automatic (time sync issues cause codes to be rejected).

---

## Changing Your Verification Method

You can switch from WhatsApp to the Authenticator app (or the other way round) at any
time. The change is a **reset**: your current method is removed and you choose a fresh one
the next time you sign in. Two-factor authentication itself stays switched on throughout.

### Changing it yourself

1. Go to your **Profile** page.
2. Next to **Two-Factor Authentication** click **Change 2FA Method**.
3. Read the popup carefully — it lists exactly what will happen:
   - your current method stops working immediately;
   - you are signed out straight away;
   - two-factor stays on — you must pick and confirm a new method to get back in;
   - a confirmation email is sent to you.
4. Have your phone (for WhatsApp / text message) or an authenticator app ready **before**
   you continue.
5. Enter your password, tick the acknowledgement box and click **Reset 2FA Method**.
6. Sign in again. You will land on the method-selection screen with a note that your
   method was reset, choose a new one and set it up as described above.

### Asking your administrator

If you cannot sign in at all (lost phone, changed number, lost authenticator app), your
administrator can do the same reset from your user page with **Reset 2FA Method**. They will see the same popup,
including a reminder to confirm the request really came from you. You receive an email
telling you the reset happened and who did it — **if you did not ask for it, contact your
administrator immediately.** Your next sign-in then asks you to choose a new method.

---

## Disabling 2FA

Turning 2FA off needs your **password and a current code**, for every user. This is so that
someone using your open session (a laptop left unlocked, a stolen browser) cannot remove your
second factor. **Edit profile** no longer has an off switch — once 2FA is on it shows
"On — turn it off from your user page".

1. Go to your **Profile** page (**Profile menu → My Profile**).
2. Next to **Two-Factor Authentication** click **Turn off 2FA**.
3. Read the popup — it lists what happens: codes stop being asked for, sign-in needs only your
   password, and you and your firm's other company admins are emailed.
4. Type your **password**.
5. Type the **current code**: from your authenticator app, or press **Send code** first for
   WhatsApp or text message (one code per 30–60 seconds).
6. Tick **I understand sign-in will no longer ask for a code.** and click **Turn off 2FA**.

```mermaid
flowchart LR
    A["Turn off 2FA"] --> B{"Password right?"}
    B -- "no" --> X1["Refused<br/>(counts toward the lock)"]
    B -- "yes" --> C{"Code right?"}
    C -- "no" --> X2["Refused<br/>(3 tries per 10 minutes)"]
    C -- "yes" --> D["2FA off<br/>+ emails"]
```

2FA is then off. Your chosen method is forgotten at the same time, so if you switch 2FA back
on later you will choose a method again at your next login — delete the old CapHive entry from
your authenticator app if you had one. If 2FA was on but you never chose a method, the popup
asks for your password only.

- A **wrong password** counts toward the account lock, exactly like a wrong sign-in (6 in a row
  lock the account).
- A **wrong code** shows how many attempts are left; after 3 wrong codes in 10 minutes you must
  wait 10 minutes.
- An **administrator cannot turn your 2FA off**. On someone else's page **Turn off 2FA** is shown
  greyed out with the reason; they use **Reset 2FA Method** instead, which keeps 2FA on.

> If you cannot log in because you have lost access to your code (no WhatsApp, no text messages, no app, no phone), contact your administrator to reset your 2FA method.

---

## Required for CapHive support and super users

CapHive's own **support** and **super** users can sign in as clients (**Login as**), so their
accounts must have a second factor. Each region (IN, US) has an **enforcement date**; company
admins, employees, investors and advisors are **not** required — for them 2FA stays optional.

```mermaid
timeline
    title A support user's notice period
    Before the date : amber banner with the date and Set up now
    On the date : sign-in asks you to set up a method first : red banner for a session that began earlier : Login as refused until you set up
```

| When | What a support / super user without a method sees |
|---|---|
| Before the date | An amber banner on every page: "Two-factor authentication becomes required for your role (Support) on 01/12/2026." with **Set up now** |
| From the date | Sign-in shows **Set Up Two-Factor Authentication** with "required for your role" — you choose a method before you get in |
| From the date, in a session that began earlier | A red banner, and **Login as** is refused with a **Set up now** button |
| After setting up | No banner; **Required for your role** badge on your profile; no **Turn off 2FA** |

**Set up now** signs you out; sign in again and choose a method. The **authenticator app** works
without a phone number. If you lose your phone later, another support user or a company admin
can **Reset 2FA Method** for you.

## Frequently Asked Questions

### Navigation and getting there

**Where do I turn on two-factor authentication?**
Click your avatar in the top-right corner to open the **Profile menu**, choose **My Profile**, click **Edit**, switch on **Enable Two-Factor Authentication** and save. See [Enabling 2FA](#enabling-2fa).

**Where can I see whether 2FA is on for my account and which method I use?**
Open **Profile menu → My Profile**. The **Two-Factor Authentication** row shows Yes or No and a badge with your method, or **Method not chosen yet** if you have not completed setup.

**Where is the Change 2FA Method button?**
On **My Profile**, next to **Two-Factor Authentication**. It only appears once 2FA is on and a method has been chosen; before that your next sign-in already takes you to method selection.

**Where does an administrator reset 2FA for someone else?**
Open the top-bar [**Company menu → User**](/users), open the person's profile and click **Reset 2FA Method** in the **Two-Factor Authentication** row. See [Asking your administrator](#asking-your-administrator).

**Where is the method-selection screen?**
You cannot open it from a menu. CapHive shows the **Set Up Two-Factor Authentication** screen automatically at sign-in when 2FA is on but no method is set, either the first time or after a reset. See [Choosing Your Verification Method](#choosing-your-verification-method).

### Enabling, changing and disabling 2FA

**How do I enable 2FA?**
Go to **My Profile** → **Edit**, switch on **Enable Two-Factor Authentication** and save. Setup finishes the next time you sign in, when you choose a method and confirm a code.

**Which verification methods can I choose from?**
**WhatsApp**, **Authenticator App**, and **Text message (SMS)** where CapHive has text messages switched on and your mobile number can receive them. The phone options only appear if your profile has a mobile number, and WhatsApp also needs WhatsApp enabled on your profile.

**How do I set up the authenticator app method?**
Choose **Authenticator App** at sign-in, scan the QR code with Google Authenticator, Microsoft Authenticator or Authy, then type the current 6-digit code and click **Confirm & Enable 2FA**. The [Authenticator App Setup Guide](authenticator_app_setup_user_guide) walks through it step by step.

**How do I change my verification method?**
On **My Profile** click **Change 2FA Method**, enter your password, tick the acknowledgement box and click **Reset 2FA Method**. Sign in again and choose a new method. See [Changing Your Verification Method](#changing-your-verification-method).

**How do I turn 2FA off?**
On **My Profile** click **Turn off 2FA**, type your password and a current code, tick the box and click **Turn off 2FA**. See [Disabling 2FA](#disabling-2fa).

**Why does turning 2FA off need my password and a code?**
So that someone using your open session cannot remove your second factor. Both are checked in the same step, a wrong password counts toward the account lock, and you and your firm's other company admins are emailed.

**Why can't my administrator turn my 2FA off?**
Switching someone else's 2FA off is how accounts are taken over, so only you can do it. If you lost your phone, ask for **Reset 2FA Method**: it keeps 2FA on and you choose a new method at your next sign-in.

**Why must CapHive support and super users use 2FA?**
They can sign in as clients with **Login as**, so a stolen support password would reach many firms. From the region's enforcement date they set up a method at sign-in. See [Required for CapHive support and super users](#required-for-caphive-support-and-super-users).

**Why is there no Turn off 2FA button on my profile?**
Either 2FA is off, you are a support or super user (the **Required for your role** badge says so), or support is viewing your account as you.

**How do I make the WhatsApp option available?**
Add your mobile number in **Mobile Phone** on your profile's **Edit** page and switch on **Whatsapp enabled**, which you should only do if that number uses WhatsApp. You can do this yourself or ask a company admin.

**Who can reset someone's 2FA method?**
You can reset your own. A company admin of your organisation or CapHive support can reset yours from your user profile, which is the route to take when you are locked out.

### Why use two-factor authentication

**Why should I turn on 2FA?**
A stolen or guessed password is no longer enough to get into your account; an attacker would also need your phone. CapHive holds investor, fund and banking data, so a second factor protects both you and your organisation.

**Which method should I choose?**
**WhatsApp** is easiest: nothing to install, but you need mobile signal. **Authenticator App** is the most secure and works offline. **Text message** suits users without WhatsApp who still want a code sent to them.

**What happens if I don't enable 2FA?**
You sign in with your password or a magic link alone. Your account keeps working, but it is only as safe as your password and your email inbox.

### What happens when I…

**What happens when I switch on Enable Two-Factor Authentication and save?**
Nothing changes in your current session. At your next sign-in, after your password or magic link, CapHive shows the method-selection screen and you are not signed in until you confirm a code. No email is sent.

**What happens when I confirm a code during setup?**
Your chosen method is saved, you are signed in, and from then on every sign-in asks for a code by that method. Your profile shows the method as a badge in the **Two-Factor Authentication** row.

**What happens when I reset my own 2FA method?**
Your current method stops working immediately, you are signed out, and a confirmation email is sent to you. 2FA stays on, so your next sign-in takes you to method selection with a note that your method was reset.

**What happens when an administrator resets my 2FA method?**
Your old method stops working and you receive an email saying the reset happened and who did it. You stay signed in on any current session, and your next sign-in asks you to choose a new method; if you did not ask for the reset, contact your administrator at once.

**What happens when I switch 2FA off?**
Codes are no longer asked for from your next sign-in, your chosen method is forgotten, and you and your firm's other company admins are emailed. If you switch 2FA back on later you pick a method again, so delete the old CapHive entry from your authenticator app.

**What happens when I press Set up now on the banner?**
You are signed out with "Sign in again to set up two-factor authentication." Signing in then shows the method-selection screen; once you confirm a code the banner is gone and a "turned on" email is sent.

**What happens if I enter the wrong code?**
You see "Invalid code" with the number of attempts left. After 3 failed attempts CapHive shows "Too many failed attempts. Please sign in again." and you start again from the sign-in page.

### Troubleshooting and edge cases

**I chose WhatsApp mode but I am not receiving codes.**
Check that your WhatsApp number is correct on your profile and that the phone has signal, then click **Resend code via WhatsApp**. If it still fails, ask your administrator to confirm WhatsApp is enabled on your account and the number is right.

**What if I lose my phone and use WhatsApp or text messages?**
Contact your administrator and ask them to reset your 2FA method. You will pick a new method at your next sign-in, on a new number if needed.

**What if I lose my phone and use an authenticator app?**
If you can still open the app on the old phone, transfer the account to the new phone first; see the [Authenticator App Setup Guide](authenticator_app_setup_user_guide). If the old phone is gone, ask your administrator to reset your 2FA method and set it up again at your next sign-in.

**Does 2FA apply to magic link logins?**
Yes. If 2FA is enabled, you must complete verification after clicking a magic link too, and you land on the linked page once the code is accepted.

**Can an administrator enable 2FA for me without my involvement?**
No. The **Enable Two-Factor Authentication** switch only appears when you edit your own profile, and you must complete the setup yourself at your next sign-in. Administrators can only reset a method you have already chosen.

**Why does the WhatsApp option appear greyed out?**
Your profile has a mobile number but WhatsApp is not enabled on it. Switch on **Whatsapp enabled** on your profile's **Edit** page, or ask your administrator to.

**Why is there no WhatsApp or text message option at all?**
Both phone options are hidden when your profile has no mobile number, because there is nowhere to send a code. Add your number on your profile's **Edit** page, or choose **Authenticator App**.

**Sign-in says "We can't send a verification code to your phone right now". What should I do?**
Your saved method is WhatsApp or text message but your account can no longer receive codes, for example the number was removed or WhatsApp was switched off. Contact your administrator to fix the number or reset your 2FA method.

**My authenticator codes are always rejected. Why?**
The most common cause is the phone's clock being out of sync; set date and time to automatic and try the next code. The [Authenticator App Setup Guide](authenticator_app_setup_user_guide) has more troubleshooting steps.

**Can I undo a 2FA reset?**
No. Once reset, the old method cannot be restored; you set up a method again at your next sign-in, which can be the same type as before.

## Related Guides

- [Authenticator App Setup Guide](authenticator_app_setup_user_guide) — installing an app, scanning the QR code and moving it to a new phone.
- [User Role Management](user_role_management_user_guide) — the company admin role that can reset another user's 2FA method.
- [Entities](entities_user_guide) — your organisation's profile and settings.
- [Audit Trail](audit_trail_user_guide) — where changes to user settings, including 2FA, are recorded.
