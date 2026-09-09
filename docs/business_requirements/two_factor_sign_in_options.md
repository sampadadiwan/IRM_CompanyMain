# How users receive their sign-in code

When two-factor authentication is switched on for a user, CapHive asks for a six-digit code
after their password. There are three ways to receive that code.

This page is for client conversations: which options a user will see, who controls each, and
what to say when an expected option is missing. The engineering detail sits in
[`docs/technical/two_factor_gates_and_validations.md`](../technical/two_factor_gates_and_validations.md).

---

## 1. The three methods

A user is offered every method they qualify for, and picks one.

| Method | Availability | What the user needs | If they lose access |
|---|---|---|---|
| **Authenticator app**<br>Google Authenticator, Authy, 1Password | Always offered | A free app on their phone. No signal or SIM needed — works on a plane or abroad | **Self-service** — 8 one-time backup codes are issued at setup |
| **WhatsApp**<br>Code sent to their WhatsApp | Conditional | A phone number on file, and an administrator confirming that number is on WhatsApp | Administrator reset. No backup codes |
| **Text message**<br>Standard SMS | Conditional | A valid **mobile** number on file, and the feature switched on for their region | Administrator reset. No backup codes |

> **Worth saying to a client up front.** Only the authenticator app lets a user recover on
> their own. WhatsApp and text message have no backup codes, so a user who changes phone
> number and loses access to the old one needs an administrator to reset their method before
> they can sign in again.

---

## 2. Who controls each setting

A setting held higher in this table overrides everything below it.

| Setting | Held by | Applies to | Effect when off |
|---|---|---|---|
| Text messaging, per region | **CapHive** | Every client on that regional deployment | Text message option disappears for everyone in that region |
| Countries we can text | **CapHive** | All regions | Codes to numbers in an unlisted country are not delivered |
| Two-factor on / off | **Client administrator** | One user | That user signs in with their password alone |
| WhatsApp confirmed | **Client administrator** | One user | WhatsApp shows greyed out, with a note to contact their administrator |
| Phone number on file | **Client administrator** | One user | Both phone methods disappear; only the authenticator app is offered |
| Which method to use | **The user** | Themselves | They are asked to choose the first time they sign in |

---

## 3. What makes a phone number usable

Numbers are stored as a country code plus the number. Most "the text option is missing"
questions come down to one of these four points.

| Rule | Why it matters | Example |
|---|---|---|
| **It has to be complete** | A number with a missing or extra digit is rejected when saved. Nine digits where the country expects ten is the most common cause | ✕ `944902587`  ·  ✓ `9449025878` |
| **Text messages need a mobile** | A landline is a valid number and saves fine, but cannot receive a text — so the option is not offered | Office numbers are the usual culprit |
| **Don't type the country code twice** | The country code has its own field. Pasting a full international number into the number field counts it twice and is rejected | ✕ `+91…` in the number field  ·  ✓ `91` in the country field |
| **Any country is accepted** | A user's number need not match the region their account sits in. Someone on the US platform with an Indian mobile is offered text messages like anyone else | Subject to the countries we can text |

> **The check applies to the user screen, not to every route in.** It runs when someone adds
> or edits a number on a user, and not on records that were already there. Numbers arriving
> from a bulk import, from an investor access row, or replicated from another region are
> accepted as given — those systems mirror a source we don't control, and refusing their data
> would stall the transfer rather than improve it. So an existing user with an incomplete
> number keeps working normally and can still be edited in every other respect, but will not
> see the text message option until the number itself is corrected.

---

## 4. Limits on sending codes

Text messages cost money per message and are a known target for fraud, so sending is capped.
Users rarely meet these limits; support occasionally will.

| Limit | Applies to | What the user sees |
|---|---|---|
| 1 code per minute | Each phone number | "Please wait a moment before requesting another code." |
| 5 codes per hour | Each phone number | Nothing arrives, though the screen said a code was on its way |
| 10 codes per day | Each phone number, and each user | As above |
| 3 wrong codes | Each sign-in attempt | "Too many failed attempts. Please sign in again." |

> **Why "a code is on its way" can be followed by nothing.** The screen confirms the request
> before the message has actually left, because sending happens in the background. If an
> hourly or daily limit has already been reached, the message is stopped after that
> confirmation. Expected behaviour rather than a fault — every attempt is recorded, so
> support can confirm exactly what happened and when.

---

## 5. Quick answers for support

| The client says… | The likely cause | What to do |
|---|---|---|
| "There's no text message option" | Number is incomplete, is a landline, or the region doesn't have the feature on | Check the number first; it explains most cases |
| "WhatsApp is greyed out" | The administrator hasn't confirmed the number is on WhatsApp | Client administrator ticks the WhatsApp setting on the user |
| "Only the authenticator app is offered" | No phone number on file | Client administrator adds one |
| "It said a code was sent but nothing came" | A sending limit was reached, or the number can't receive texts | We can confirm from the delivery record |
| "I've lost my phone" | — | Authenticator: use a backup code. WhatsApp or text: administrator resets the method, user chooses again |
| "It won't let me save this number" | The number is incomplete or the country code was entered twice | Correct the number; the error names the country code being applied |
