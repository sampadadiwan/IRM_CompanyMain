# Support Console — User Guide

The Support Console lets CapHive support staff ask an AI assistant why something looks the way it does for one client — it reads the code CapHive is running and that client's data, read-only, and answers with the code and the rows behind the answer.

> **Where to find it:** Profile menu (your avatar, top right) → **Support Console**. Then pick a client from the switcher. Needs the **Support** role and an enabled support mapping to the client in [**Support Mappings**](/support_client_mappings), and the client must have support access switched on.

## Who can use it

| You | What you can do |
|---|---|
| Support user, mapped to the client | Pick the client, ask questions, continue earlier conversations |
| Support user, not mapped (or mapping ended) | See only the clients you are mapped to; nothing for others |
| Super user without the Support role | Not the console itself; reviews the record of lookups and gets alerts |
| Client employees and investors | Nothing — the console is internal to CapHive |

A client appears in your switcher only while all three are true: you have a support mapping to it, the mapping is **enabled** and its **end date** is today or later, and the client has **support access** switched on.

## Asking a question

1. Open **Support Console** and pick the client.
2. Type your question in the box and press **Enter** (Shift+Enter adds a new line). The send button is the arrow on the right; beside it, choose **Sonnet** (faster and cheaper — the default) or **Opus** (deeper, for hard investigations).
3. While the assistant works you see what it is doing — "Reading …", "Searching the code for …", "Looking up data" — and the send button becomes **Stop**.
4. The answer ends with **Where this comes from**: the code locations and the lookups it used. **How this was worked out** lists every step it took.

Good questions name the thing you can see and ask *why*: "Why does Ravi K show a zero closing balance in Fund I for Q3?", "Why is TSTF2 marked Overpaid on Call 2?", "Why did the distribution email not go out to Investor X?".

Shortcuts: **Ctrl+K** (Cmd+K on a Mac) starts a new chat; **/** puts the cursor in the question box.

## Conversations

Each conversation belongs to one client. The left sidebar lists that client's conversations, newest first, grouped **Today**, **Yesterday**, **Previous 7 days** and **Older**; hover one to see who started it and when. **Search chats** appears once a client has more than five. Follow-up questions in a conversation remember what was already found. Conversations are deleted 90 days after their last message.

## What it can and cannot do

| Can | Cannot |
|---|---|
| Read the code CapHive is running and explain how a figure is worked out | Change any data, re-run anything, or send emails or WhatsApp messages |
| Look up the client's records (read-only) and show the rows behind an answer | Look at any other client in the same conversation |
| Explain who changed a record and when (the change history) | Open document files, use search, or reach outside providers |
| Describe the fix a problem needs | Make that fix — an engineer or the client does |

## The footer

Under the box: **Code version** is the version of CapHive the answer was based on. **Data as of N seconds ago** says how far the data behind the answer was behind the live system; it turns red when that is more than 60 seconds.

## What is recorded

Every lookup the assistant makes is recorded with who asked, the client, the statement, whether it ran, was refused or failed, and how many rows came back — not the rows themselves. CapHive super users review this record, and are alerted in their notifications if a lookup ever returned another client's data.

## Frequently Asked Questions

### Navigation and getting there

**Where do I find the Support Console?**
Open the Profile menu (your avatar, top right) and click **Support Console**, under **Support Mappings**. It appears only for users with the **Support** role.

**Why don't I see Support Console in my menu?**
The menu item is shown only to users with the **Support** role. A super user without that role does not see it either. Ask a CapHive super user to add the Support role to your user.

**Why does the Support Console say I am not mapped to any client?**
You see "You are not mapped to any client with support access. Ask a super user to add a support mapping." when you have no enabled, in-date support mapping to a client that has support access on. Ask a super user to add or extend your mapping in [**Support Mappings**](/support_client_mappings).

**Why is a client missing from the client switcher?**
A client is listed only while your support mapping to it is enabled, its end date is today or later, and the client has support access switched on. If any of these is not true the client is left out, and opening its console directly shows "Not authorized."

**How do I switch to another client?**
Use the client switcher at the top of the chat. It lists only the clients you are mapped to. Switching opens that client's console with its own conversations; a conversation never moves from one client to another.

### Creating, updating and managing conversations

**How do I ask the Support Console a question?**
Pick the client, type your question in the box and press **Enter** or click the arrow button. Shift+Enter adds a new line. Questions can be up to 4,000 characters; an empty question is refused with "Please type a question."

**How do I start a new conversation?**
Click **New chat** at the top of the sidebar, or press **Ctrl+K** (Cmd+K on a Mac). A new conversation starts with your next question.

**How do I continue an earlier conversation?**
Click it in the sidebar. Its questions and answers are shown, and a follow-up remembers what was already found, so you do not need to repeat the details.

**Should I use Sonnet or Opus in the Support Console?**
Start with **Sonnet**, the default: it is faster and costs about half as much. Switch the selector beside the send button to **Opus** for a hard investigation that Sonnet did not crack. A conversation keeps your last choice, and each answer shows which model wrote it.

**How do I stop an answer that is going the wrong way?**
Click **Stop** — the send button turns into Stop while an answer is being worked out. The answer is marked **Stopped** and you can ask again straight away, for example with a narrower question.

**How do I copy a question or an answer?**
Hover over it and click the copy icon. **Copy answer** copies the answer's text, including the Where this comes from section, to paste into a ticket or an email.

**Can I search my conversations?**
Yes, once a client has more than five conversations a **Search chats** box appears above the list. It filters the conversations listed for that client by their first question.

**How long are Support Console conversations kept?**
Ninety days after their last message. After that the conversation and its working notes are deleted; the record of lookups made in it is kept for audit.

**How do I start or stop the support machine?**
Use the badge at the top right of a conversation. It shows **Machine running**, **Machine stopped**, **Machine starting…** or **Machine stopping…**. When the machine is stopped, **Start** turns it on, and it is ready in about 2 minutes, once the badge shows **Machine running**. When it is running, **Stop** turns it off. The popup tells you how many answers are in progress: the machine is shared by every support user for every client, so stopping it cuts those answers off. Any user with the support role can start or stop it.

**What happens when I ask a question while the machine is stopped?**
The question starts the machine. The answer shows "Starting the support machine (about 2 minutes)" as its first step, waits for the machine to be ready, and then carries on as normal. You do not need to press Start first.

**Why did the support machine stop on its own?**
It stops itself after 60 minutes with no questions, to avoid running all day for nothing. The time counts from the last question or the last start, whichever is later, and it never stops while an answer is in progress. The next question, or **Start**, turns it back on.

**What is "Conversation: 64k tokens · ≈ $0.41" in the footer?**
How much work Claude has done in this conversation so far: the tokens it read and wrote across every answer, and what that would cost at Claude's API prices. It is an estimate for comparison. On the subscription the console uses, the actual charge is a flat monthly plan, so a long conversation mainly uses up more of the plan's limits. Answers from before this was recorded are not counted.

### Why use the Support Console

**Why use the Support Console instead of asking an engineer?**
Most "why does this look wrong" tickets can be answered from the code and the client's records. The console reads both and answers in minutes, with the code locations and rows behind the answer, so you can check it before replying to the client and hand engineers a ready diagnosis when a fix is needed.

**What kind of questions work best?**
Questions about something you can see, asking why: a figure, a status, a missing email or record. Name the client's fund, investor or record as it appears on screen, for example "Why is TSTF2 marked Overpaid on Call 2 in Demo Fund 1?". Open-ended requests to list everything work less well; ask for a summary instead.

**Can I trust the answers?**
Check them: every answer ends with **Where this comes from**, naming the code it read and the lookups it made, and **How this was worked out** lists each step. The data is the client's live data, usually only seconds old — the footer says how old.

### What happens when I …

**What happens when I ask a question?**
The assistant reads CapHive's code and looks up the client's records, read-only, then writes the answer. Each lookup is recorded with your name and the client. Nothing in the client's data changes and no one is notified.

**What happens when I ask it to fix something?**
It explains what the fix would be and says it cannot make it. The Support Console has no way to change data, re-run anything or send messages; the fix is done in CapHive by the client or an engineer.

**What happens when I ask about another client?**
The answer says it can only look at the client of this conversation. Pick the other client in the switcher and ask there, if you are mapped to it.

**What happens when my support mapping ends?**
The client disappears from your switcher, and a question in an open conversation for it is refused with "Your support access to <client> has ended." Ask a super user to extend the mapping in [**Support Mappings**](/support_client_mappings).

**Is the client told that I used the Support Console?**
No. The console is internal to CapHive and sends nothing to the client or its investors. It only works for clients that have switched on support access for CapHive.

**Who sees the record of what I looked up?**
CapHive super users. Every lookup is recorded with who asked, the client, the statement and how many rows came back — not the rows themselves — and super users are alerted if a lookup ever returned another client's data.

### Troubleshooting and edge cases

**Why does the Support Console say it is unavailable right now?**
"The Support Console is unavailable right now. Try again in a few minutes." means the assistant's service could not be reached or could not read the data. Your question is put back in the box; press Enter to try again a little later.

**Why does it say "The Support Console has reached its usage limit. Try again later."?**
The assistant runs on a Claude plan with a usage limit that resets every few hours. When the limit is reached, no question can be answered until it resets. Your question is put back in the box; ask again later. Nobody needs to be told — the team sees the limit too.

**Why did I get "Already working on a question in this conversation."?**
Only one question runs per conversation at a time. Wait for the current answer, click **Stop**, or start a **New chat** for a separate question.

**Why did I get "That took too long. Try a narrower question."?**
The answer took longer than the console allows. Ask about one fund, investor, period or record at a time rather than everything at once.

**Why does an answer say "The answer was interrupted. Please ask again."?**
The service was restarted while the answer was being worked out. Ask the question again; the conversation is not blocked.

**Why is the footer's "Data as of" shown in red?**
The data behind the answer was more than 60 seconds behind the live system. A record changed in the last minute may not be reflected; ask again shortly if that matters.

**Why does an answer say it could not see a document or search result?**
The Support Console cannot open document files, use the search boxes or contact outside providers such as e-sign or KYC services. It can see the records about documents and messages, but not their contents or delivery by outside services.

## Related Guides

- [Customer Support Agent](customer_support_agent_user_guide) — the client-facing support chatbot and CS reviews.
- [Audit Trail](audit_trail_user_guide) — the change history the console uses to answer "who changed this".
- [AI Features](ai_features_user_guide) — the other AI tools in CapHive.
- [Investor KYC](investor_kyc_user_guide) — background for KYC questions.
- [Capital Calls](capital_calls_user_guide) — background for call and remittance questions.
