# Two-Factor Authentication User Guide

**Two-Factor Authentication (2FA)** adds an extra layer of security to your account. After entering your password, you will be asked for a one-time code before you are signed in. This guide covers enabling 2FA, choosing your delivery method, and logging in.

---

## Table of Contents

1. [Overview](#overview)
2. [Enabling 2FA](#enabling-2fa)
3. [Choosing Your Verification Method](#choosing-your-verification-method)
4. [WhatsApp Mode — Setup](#whatsapp-mode--setup)
5. [Authenticator App Mode — Setup](#authenticator-app-mode--setup)
6. [Logging In with 2FA](#logging-in-with-2fa)
7. [Using Backup Codes](#using-backup-codes)
8. [Disabling 2FA](#disabling-2fa)
9. [Frequently Asked Questions](#frequently-asked-questions)

---

## Overview

When 2FA is enabled, signing in requires two things:

1. **Something you know** — your password
2. **Something you have** — your phone (WhatsApp message or authenticator app)

```mermaid
sequenceDiagram
    participant U as You
    participant S as System
    participant P as Your Phone

    U->>S: Enter email + password
    S->>S: Password correct
    S->>P: Send code (WhatsApp) or prompt app
    U->>S: Enter 6-digit code
    S->>U: Signed in
```

---

## Enabling 2FA

You can only enable or disable 2FA for your own account.

1. Go to your **Profile** page (click your name in the top-right corner)
2. Click **Edit Profile**
3. Check the **Enable Two-Factor Authentication** box
4. Click **Save**

2FA does not take effect immediately. The next time you log in, you will be guided through choosing a verification method and completing setup.

---

## Choosing Your Verification Method

The first time you log in after enabling 2FA, you will see the **Set Up Two-Factor Authentication** screen with two options:

| Option | How it works | Best for |
|---|---|---|
| **WhatsApp** | A code is automatically sent to your WhatsApp each time you log in | Users who prefer simplicity and always have their phone |
| **Authenticator App** | You read a code from an app on your phone (works offline) | Users who want the most secure option |

> If WhatsApp is not enabled for your account, the WhatsApp option will be shown as unavailable. Contact your administrator to enable it.

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
        S->>U: Authenticator mode active + backup codes shown
    end
```

---

## WhatsApp Mode — Setup

1. On the mode selection screen, choose **WhatsApp**
2. A 6-digit code is immediately sent to your WhatsApp number
3. Enter the code and click **Confirm & Enable 2FA**
4. You are signed in — setup is complete

No app to install. No QR code to scan. Each time you log in going forward, a code is sent to your WhatsApp automatically.

> WhatsApp mode does not generate backup codes. If you lose access to your WhatsApp number, contact your administrator to reset your 2FA.

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

### Step 4: Save Your Backup Codes

You will be shown **8 backup codes**. Save these immediately — they are shown only once and cannot be recovered. Store them in a password manager, safe, or printed copy.

```mermaid
sequenceDiagram
    participant U as You
    participant A as Authenticator App
    participant S as System

    U->>A: Install app + scan QR code
    A->>U: Show 6-digit code
    U->>S: Enter code
    S->>U: Show 8 backup codes
    U->>U: Save backup codes
    S->>U: Signed in
```

---

## Logging In with 2FA

### WhatsApp Mode

1. Enter your email and password
2. A code is automatically sent to your WhatsApp
3. Enter the code on the verification screen and click **Verify**
4. If you did not receive the code, click **Resend code via WhatsApp**

### Authenticator App Mode

1. Enter your email and password
2. Open your authenticator app and read the current 6-digit code
3. Enter the code and click **Verify**
4. If your WhatsApp is also enabled on your account, you may optionally click **Send code via WhatsApp** instead

### Failed Attempts

After **3 failed attempts**, your session is reset and you must sign in again from the beginning.

Codes refresh every 30 seconds — if one fails, wait for the next one and try again. Make sure your phone's clock is set to automatic (time sync issues cause codes to be rejected).

---

## Using Backup Codes

Backup codes are available for **Authenticator App mode** only. You receive 8 codes when you complete setup. Each code can be used **once**.

To use a backup code, enter it on the verification screen instead of a 6-digit code.

> After using a backup code, visit your profile to regenerate a fresh set if needed. If you run out of backup codes and lose your authenticator app, contact your administrator.

---

## Disabling 2FA

1. Go to your **Profile** page
2. Click **Edit Profile**
3. Uncheck **Enable Two-Factor Authentication**
4. Click **Save**

2FA is immediately disabled. You will no longer be asked for a code at login.

> If you cannot log in because you have lost access to your code (no WhatsApp, no app, no backup codes), contact your administrator to disable 2FA for your account.

---

## Frequently Asked Questions

**Can I switch from WhatsApp mode to Authenticator mode (or vice versa)?**
Not directly from your profile yet. Contact your administrator to reset your 2FA setup — you will then be prompted to choose again on your next login.

**I chose WhatsApp mode but I am not receiving codes.**
Check that your WhatsApp number is registered correctly. Ask your administrator to verify that WhatsApp is enabled on your account and that the phone number is correct.

**What if I lose my phone?**
- WhatsApp mode: contact your administrator to disable 2FA.
- Authenticator mode: use a backup code to log in, then disable and re-enable 2FA with your new phone.

**Does 2FA apply to magic link logins?**
Yes — if 2FA is enabled, you must complete verification after clicking a magic link too.

**Can an administrator enable 2FA for me without my involvement?**
Administrators can toggle the 2FA setting on your account, but you must complete the setup (choose method and confirm) on your own next login.

**Why does the WhatsApp option appear greyed out?**
Your account does not have a WhatsApp-enabled phone number. Contact your administrator to enable it.
