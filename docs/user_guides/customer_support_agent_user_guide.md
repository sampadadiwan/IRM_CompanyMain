# Customer Support Agent — User Guide

The Customer Support Agent is an AI-powered chatbot built into the CapHive platform. It helps Fund Manager (FM) users get instant answers to platform support questions — how to use features, troubleshoot issues, and understand their data — without waiting for the support team.

When the agent cannot answer a question, it escalates the conversation to the CapHive support team, who review and respond through the CS Feedback Review Dashboard.

This guide is divided into two parts:

1. **For Fund Manager Users** — How to use the support chat to get help
2. **For the CapHive Support Team** — How to use the CS Feedback Review Dashboard to monitor quality, handle escalations, and take action

---

## Table of Contents

### Part 1: For Fund Manager Users
1. [Getting Started](#getting-started)
2. [Opening the Chat](#opening-the-chat)
3. [Asking Questions](#asking-questions)
4. [What the Agent Can Help With](#what-the-agent-can-help-with)
5. [Understanding Responses](#understanding-responses)
6. [Rating Responses](#rating-responses)
7. [Providing Feedback Notes](#providing-feedback-notes)
8. [When the Agent Escalates to a Human](#when-the-agent-escalates-to-a-human)
9. [Managing Chat Sessions](#managing-chat-sessions)
10. [Tips for Getting the Best Answers](#tips-for-getting-the-best-answers)
11. [Frequently Asked Questions (FM)](#frequently-asked-questions-fm)

### Part 2: For the CapHive Support Team
12. [Support Team Overview](#support-team-overview)
13. [Accessing the CS Feedback Review Dashboard](#accessing-the-cs-feedback-review-dashboard)
14. [Understanding the Dashboard Layout](#understanding-the-dashboard-layout)
15. [The Feedback Queue](#the-feedback-queue)
16. [The Escalation Queue](#the-escalation-queue)
17. [Using Filters](#using-filters)
18. [Reviewing a Feedback Item](#reviewing-a-feedback-item)
19. [Understanding Judge Scores](#understanding-judge-scores)
20. [Taking Actions on Feedback](#taking-actions-on-feedback)
21. [Re-testing a Question](#re-testing-a-question)
22. [Handling Escalations](#handling-escalations)
23. [Entity Scoping and Client Mappings](#entity-scoping-and-client-mappings)
24. [Frequently Asked Questions (Support Team)](#frequently-asked-questions-support-team)

---

# Part 1: For Fund Manager Users

---

## Getting Started

The Customer Support Agent is automatically available on your CapHive dashboard if your entity (organisation) has the feature enabled. There is nothing to install or configure — simply look for the chat bubble in the bottom-right corner of your dashboard.

### Who Can Use It

All FM users within an enabled entity can access the support chat:
- Company Admins
- Operations Managers
- Operations Users
- Any employee-level user

### What You Need

- A web browser logged into CapHive
- An active CapHive account within an entity that has the Customer Support Agent enabled

---

## Opening the Chat

When you navigate to your FM dashboard, you will see a floating chat bubble in the bottom-right corner of the screen:

- A speech-tail label reads **"Need help? Ask Customer Support Agent"**
- Next to it is a circular blue button with a robot icon

**To open the chat**, click anywhere on the bubble or the blue button. A chat panel will slide up from the bottom-right corner.

**To close the chat**, click the **X** (Close) button in the chat panel header, or click the bubble again.

The chat panel can also be:
- **Maximised** — Click the arrows icon (Maximize) to expand the panel to full screen. Click again to restore.
- **Dragged** — Click and hold the blue header bar to drag the panel to a different position on screen.
- **Resized** — Drag the edges of the panel to resize it.

---

## Asking Questions

Once the chat is open, you will see a welcome screen with a text input at the bottom.

### Quick-Start Suggestions

The welcome screen shows sample questions you can try:

- "How do I create a capital call?"
- "What's the process for investor onboarding?"
- "How do I generate a distribution notice?"

Click any suggestion to auto-fill it in the input box, then press **Enter** or click the **Send** button.

### Typing Your Own Question

1. Click the text input at the bottom of the chat panel
2. Type your question in plain English
3. Press **Enter** or click the blue Send button

The agent will show a "Thinking..." spinner while it processes your question. Responses typically appear within a few seconds.

---

## What the Agent Can Help With

The Customer Support Agent draws on three sources of information to answer your questions:

### 1. Platform User Guides
The agent has access to all CapHive user guides covering features such as:
- Capital calls, distributions, and commitments
- Investor onboarding and KYC
- Fund management and reporting
- Document management
- Dashboard widgets and customisation
- Notification preferences
- And many more

**Best for:** "How do I..." questions, step-by-step instructions, feature explanations.

### 2. Your Entity's Live Data
The agent can query your organisation's actual data in CapHive — investors, funds, capital calls, KYC records, and more. All queries are scoped to your entity only; the agent cannot see other organisations' data.

**Best for:** "Show me..." or "How many..." questions, data lookups, status checks.

### 3. Your Past Conversations
The agent can search your previous support conversations for context on recurring questions or follow-up queries.

**Best for:** Continuing a previous conversation topic, referencing something you asked before.

### What It Cannot Help With

- **General knowledge** unrelated to CapHive (e.g. investment advice, market data)
- **Actions that change data** — the agent is read-only; it cannot create, update, or delete records on your behalf
- **Other organisations' data** — the agent is strictly scoped to your entity
- **Highly technical or engineering-level questions** — for these, the agent will escalate to the support team

---

## Understanding Responses

The agent formats responses using rich text:

- **Headers** for organising sections
- **Bold text** for emphasis on important terms and menu paths
- **Numbered steps** for step-by-step instructions
- **Bullet points** for lists
- **Tables** for structured data
- **Code blocks** for technical references

When the agent references a specific CapHive feature, it will typically include the navigation path (e.g. "Go to **Stakeholders → Access** tab") so you can follow along in the platform.

---

## Rating Responses

After every agent response, you will see two icons beneath the message:

- **Thumbs Up** — Click if the response was helpful and accurate
- **Thumbs Down** — Click if the response was unhelpful, incorrect, or incomplete

### Why Rating Matters

Your ratings directly help improve the agent:
- **Positive ratings** confirm that the agent is answering correctly
- **Negative ratings** flag responses for review by the CapHive support team, who use them to improve guides and agent behaviour

Rating is optional but encouraged — it takes one click and makes a real difference.

---

## Providing Feedback Notes

When you click **Thumbs Down**, a text input appears below the message:

1. Type a brief note explaining what was wrong (e.g. "The steps are outdated" or "It didn't mention the new KYC tab")
2. Click **Send** to submit your note

Your feedback note is attached to the response and visible to the support team when they review flagged items. The more specific your note, the faster the team can improve the answer.

---

## When the Agent Escalates to a Human

Sometimes the agent determines it cannot fully answer your question. When this happens:

1. The agent sends a message: **"Connecting you to the CapHive support team..."**
2. The chat session is marked as **escalated**
3. An email notification is sent to the CapHive support team with your question and conversation context
4. The escalation appears in the support team's review dashboard

### What Happens Next

- The support team will review your question and the agent's conversation
- They may reach out to you via email or through the platform
- Once the issue is resolved, your chat session is unlocked and you can continue asking questions

### Reasons for Escalation

The agent may escalate for several reasons:
- **You requested it** — You asked to speak to a human
- **Low confidence** — The agent is not confident in its answer
- **Complex issue** — The question requires human judgment
- **Maximum attempts reached** — The agent tried multiple approaches but could not find a satisfactory answer

---

## Managing Chat Sessions

### Starting a New Conversation

Click the **New** button in the chat panel header to start a fresh conversation. This creates a new session — your previous conversation is saved and accessible via History.

### Viewing Past Sessions

Click the **History** button in the chat panel header. A sidebar slides open showing your past sessions with the most recent at the top. Click any session to load its messages.

### Session Auto-Expire

If you have been inactive for more than 30 minutes, the agent automatically starts a new session the next time you send a message. Your old session remains accessible via History.

---

## Tips for Getting the Best Answers

1. **Be specific** — "How do I add a notification topic preference for an investor?" works better than "How do notifications work?"
2. **Ask one thing at a time** — The agent handles single, focused questions more effectively than multi-part queries
3. **Mention the feature name** — If you know the feature (e.g. "capital calls", "investor KYC"), include it in your question
4. **Ask follow-ups** — The agent remembers the current conversation, so you can ask "Can you show me the exact steps?" after an initial answer
5. **Use the suggestions** — The sample questions on the welcome screen are designed to showcase what the agent can do well

---

## Frequently Asked Questions (FM)

**Q: Is the agent available 24/7?**
A: Yes. The agent is always available as long as the CapHive platform is running. However, if the agent escalates to a human, the support team's response time depends on their working hours.

**Q: Can the agent see my personal data?**
A: The agent can access your organisation's data in CapHive (investors, funds, capital calls, etc.) to answer data-specific questions. It cannot see other organisations' data or access anything outside CapHive.

**Q: What if the agent gives a wrong answer?**
A: Click the Thumbs Down button and leave a feedback note. This flags the response for review by the support team, who will use it to correct the agent's knowledge.

**Q: Can I use the agent on my phone?**
A: The agent is currently available on the web version of CapHive only. Mobile and WhatsApp channels are planned for a future release.

**Q: Does the agent remember previous conversations?**
A: The agent remembers messages within the current session. It can also search your past sessions for context. However, it does not carry over full context from old sessions into new ones — it searches when relevant.

**Q: Can I go back to a previous conversation?**
A: Yes. Click the **History** button in the chat header to see and switch between past sessions.

---

# Part 2: For the CapHive Support Team

---

## Support Team Overview

The CS Feedback Review Dashboard is the central hub for the CapHive support team to monitor and maintain the quality of the Customer Support Agent. It provides:

- **Feedback Queue** — Agent responses that received negative user ratings or low automated quality scores
- **Escalation Queue** — Conversations where the agent handed off to a human because it could not answer

The dashboard is designed to be a single queue for all support activity — both quality monitoring and human escalation handling happen in one place.

### Your Role

As a support team member, you use this dashboard to:

1. **Review flagged responses** — Understand why a response was flagged (user complaint or low quality score) and decide what action to take
2. **Handle escalations** — Read the conversation context when the agent escalated, and resolve the user's issue
3. **Re-test questions** — After improving guides or agent behaviour, replay the original question to verify the agent now gives a better answer
4. **Track patterns** — Spot recurring issues, missing guide content, or areas where the agent consistently struggles

---

## Accessing the CS Feedback Review Dashboard

1. Log in to CapHive with your **support team account**
2. In the left sidebar, click **CS Reviews**

Alternatively, navigate directly to: `/cs_feedback_reviews`

### Access Requirements

- You must have the **support** role in CapHive
- You will only see feedback and escalations for entities (clients) you are **mapped to** via Support Client Mapping (see [Entity Scoping and Client Mappings](#entity-scoping-and-client-mappings))

---

## Understanding the Dashboard Layout

The dashboard has three main sections:

### 1. Filters Bar (Top)

A row of dropdown filters that apply to both tabs:

| Filter | Options | Purpose |
|--------|---------|---------|
| **Entity** | All Entities, or select a specific client | Narrow results to one client |
| **Feedback Status** | All, Open, Needs Review, Resolved, Dismissed, Pending Engineering | Filter by review status |
| **Rating** | All, Positive, Negative | Filter by user's rating |
| **Judge Score ≤** | Enter a number (0–9) | Show only items scored at or below this threshold |
| **Escalation Status** | All, Open, Resolved, Dismissed | Filter escalations by status |

Click **Filter** to apply, or **Clear** to reset all filters.

### 2. Tab Navigation

Two tabs below the filters:

- **Feedback Queue (n)** — Shows the count of flagged agent responses
- **Escalation Queue (n)** — Shows the count of escalation records

Click a tab to switch views. The count in parentheses shows total items matching current filters.

### 3. Results Table

A table of items with columns specific to each tab (detailed below).

---

## The Feedback Queue

The Feedback Queue shows agent responses that need attention. An item appears here when:

- A user gave the response a **negative rating** (thumbs down), OR
- The automated **LLM judge scored the response below 5 out of 9**

High-quality responses with positive or no ratings do not clutter this queue — only items that need review appear.

### Feedback Queue Columns

| Column | Description |
|--------|-------------|
| **Entity** | The client organisation where this conversation happened |
| **User** | The FM user who asked the question |
| **Question** | The user's original question (truncated; hover to see full text) |
| **Rating** | User's rating: Negative (red badge), Positive (green badge), or dash (no rating) |
| **Judge Score** | Automated quality score out of 9. Scores of 4 or below are highlighted in red |
| **Status** | Current review status (Open, Needs Review, Resolved, Dismissed, Pending Engineering) |
| **Date** | When the feedback was created |
| **Action** | "View" button to open the detailed review page |

### Status Meanings

| Status | Meaning |
|--------|---------|
| **Open** | New item, not yet reviewed |
| **Needs Review** | Automatically flagged by the judge (low score) — requires human review |
| **Resolved** | Reviewed and action taken (e.g. guide updated, response validated) |
| **Dismissed** | Reviewed and determined to not need action (e.g. user error, irrelevant feedback) |
| **Pending Engineering** | Requires a platform change or bug fix — handed off to the engineering team |

---

## The Escalation Queue

The Escalation Queue shows conversations where the agent decided it could not answer and handed off to a human.

### Escalation Queue Columns

| Column | Description |
|--------|-------------|
| **Entity** | The client organisation |
| **User** | The FM user who was chatting |
| **Reason** | Why the agent escalated (see below) |
| **Summary** | The agent's summary of the issue (truncated; hover to see full text) |
| **Status** | Open (yellow), Resolved (green), or Dismissed (blue) |
| **Date** | When the escalation was created |
| **Action** | "View" button to open the linked feedback review page |

### Escalation Reasons

| Reason | Description |
|--------|-------------|
| **Customer Requested** | The user explicitly asked to speak to a human |
| **Low Confidence** | The agent was not confident in the answer it could provide |
| **Complex Issue** | The question requires human judgment or is multi-faceted |
| **Max Iterations** | The agent tried its maximum number of tool calls (6) without reaching a satisfactory answer |

---

## Using Filters

Filters help you focus on what matters most. Some useful filter combinations:

### "Show me urgent items"
- Feedback Status: **Open** or **Needs Review**
- Rating: **Negative**
- This surfaces items where users explicitly flagged a problem and no one has reviewed yet

### "Show me low-quality responses for a specific client"
- Entity: (select client)
- Judge Score ≤: **4**
- This shows the worst-scoring responses for that client

### "Show me open escalations"
- Switch to the **Escalation Queue** tab
- Escalation Status: **Open**
- These are conversations waiting for human intervention

### "Show me everything that has been resolved"
- Feedback Status: **Resolved**
- Useful for auditing past decisions and seeing resolution notes

---

## Reviewing a Feedback Item

Click **"View"** on any row to open the detailed review page. This page has two columns:

### Left Column — Conversation Context

#### User Question Card
Shows the original question the FM user asked, along with the user's name, entity, and timestamp.

#### Agent Response Card
Shows the full response the agent gave. This is rendered with rich formatting (headers, bold, lists, tables) so you can read it as the user saw it.

#### Tool Calls Card
If the agent used tools to answer (searched guides, queried the database, or searched past messages), this card shows:
- Which tool was called
- What query or search terms were used
- How many results were returned
- Which guide files were searched

This helps you understand **how** the agent arrived at its answer — not just what it said.

#### Guide Files Searched Card
If the agent searched user guides, this card lists every guide file that was checked, along with a **Hit** (green) or **No Match** (yellow) badge indicating whether the guide contained relevant content.

A **No Match** badge is particularly useful — it may indicate a gap in the documentation that needs to be filled.

#### Re-test Card
See [Re-testing a Question](#re-testing-a-question) below.

### Right Column — Scores and Actions

#### Status Card
Shows the current status with a coloured badge, plus who reviewed it and any resolution notes.

#### User Feedback Card
Shows the user's rating (Positive, Negative, or No Rating) and any feedback notes they left.

#### Judge Scores Card
Shows the automated quality scores (see [Understanding Judge Scores](#understanding-judge-scores) below).

#### Linked Escalation Card
If this conversation was escalated, shows the escalation reason and summary with a yellow border.

#### Actions Card
The form for taking action on this item (see [Taking Actions on Feedback](#taking-actions-on-feedback) below).

---

## Understanding Judge Scores

Every response from the Customer Support Agent is automatically scored by an AI judge on three dimensions:

| Dimension | Score Range | What It Measures |
|-----------|------------|------------------|
| **Completeness** | 0–3 | Did the response fully answer the question? Were any steps or details missing? |
| **Grounding** | 0–3 | Was the response based on actual user guides or real data? Or did the agent make things up? |
| **Actionability** | 0–3 | Did the response tell the user exactly what to do? Were the steps clear and specific? |
| **Total** | 0–9 | Sum of the three scores |

### Score Interpretation

| Total Score | Interpretation | Action Needed |
|-------------|---------------|---------------|
| **7–9** | Good to excellent response | No action needed unless user flagged it |
| **5–6** | Acceptable but could be better | Review if time permits; consider guide improvements |
| **3–4** | Poor response | Review promptly; likely missing guide content or incorrect information |
| **0–2** | Very poor response | Review immediately; may indicate a systematic issue |

### Issues Flagged

The judge may also flag specific issues (shown as a bullet list under the scores). Common issues include:
- Missing steps in a procedure
- Information not grounded in any source
- Vague or generic advice instead of specific instructions
- Incorrect feature names or navigation paths

---

## Taking Actions on Feedback

At the bottom of the right column on the detail page, you will find the **Actions** card (only shown for items that are not yet resolved or dismissed).

### Steps to Take Action

1. **Read the conversation** — Understand the user's question and the agent's response
2. **Check the judge scores** — See where the response fell short
3. **Review the tool calls** — Understand what sources the agent used
4. **Write resolution notes** — This field is required. Describe what action you took or why you chose this status. For example:
   - "Updated the KYC guide section 3.2 with PAN resubmission steps"
   - "Response was correct — user misunderstood the navigation"
   - "Bug in capital call date picker — forwarded to engineering"
5. **Choose an action:**

| Action | When to Use |
|--------|-------------|
| **Resolve** | You have addressed the issue (updated a guide, confirmed the response was correct, contacted the user) |
| **Dismiss** | The flag is not actionable (user error, irrelevant feedback, duplicate) |
| **Pending Engineering** | The issue requires a code change, bug fix, or platform improvement — it cannot be fixed by updating guides |

A confirmation dialog will appear before each action is applied.

### Best Practices for Resolution Notes

- Be specific about what you changed: "Added section on notification preferences to the investor_access_tutorial.md guide"
- If dismissing, explain why: "User asked about a third-party integration not related to CapHive"
- If marking as pending engineering, describe the expected fix: "Agent is returning stale data for capital call amounts — needs cache invalidation fix"

---

## Re-testing a Question

After you have improved a guide or made changes that should improve the agent's answer, you can **replay the original question** through the agent to verify the improvement.

### How to Re-test

1. Open the detail page for a feedback item
2. Scroll down to the **Re-test** card (below the tool calls section in the left column)
3. Click **"Re-test this question"**
4. A confirmation dialog appears: "This will run the question through the agent again. Proceed?"
5. Click **OK**

### What Happens

- The agent receives the exact same question in a **new session**
- It processes the question using its current knowledge (including any guide updates you made)
- The new response appears directly on the page, below the Re-test heading
- You can compare the new response side-by-side with the original response above

### When to Re-test

- After updating a user guide that was missing information
- After correcting a guide that had outdated steps
- After verifying that a data issue has been fixed
- Before resolving a feedback item, to confirm the improvement

### Important Notes

- Re-testing creates a new chat session under your support account — it does not affect the original user's session
- The re-test uses the **current state** of the guides and data, so it reflects any changes you have made since the original response
- If the re-test still produces a poor answer, you may need to make further guide improvements before resolving the item

---

## Handling Escalations

When the agent escalates a conversation, the FM user's chat session is **locked** — the agent stops responding until the escalation is resolved.

### Escalation Workflow

1. **Escalation appears** in the Escalation Queue with status "Open"
2. **Review the context** — Click "View" to see the full conversation, the agent's attempted answers, and the escalation reason/summary
3. **Take action** — This may involve:
   - Reaching out to the user via email to answer their question directly
   - Updating a guide so the agent can handle similar questions in future
   - Investigating a platform issue if the question revealed a bug
4. **Resolve the escalation** — On the detail page, write resolution notes and click "Resolve"
5. **Session unlocked** — The user's chat session is automatically unlocked, and the agent can handle new messages from that user

### If the Escalation is Not Actionable

If the escalation was triggered inappropriately (e.g. the user was testing the system, or the question was outside the platform's scope), you can **Dismiss** it with a note explaining why.

---

## Entity Scoping and Client Mappings

The dashboard respects your **Support Client Mapping** — you will only see feedback and escalations for the entities (clients) you are assigned to.

### How It Works

- Each support team member is mapped to one or more client entities via Support Client Mapping
- The Entity dropdown in the filters only shows your mapped entities
- All feedback and escalation data is scoped to those entities

### If You Cannot See Expected Data

- Verify your Support Client Mapping is **enabled** (check with your admin under Support Mapping in the sidebar)
- Verify the mapping has not expired (mappings have an end date)
- Verify the entity has a Customer Support Agent configured and enabled

---

## Frequently Asked Questions (Support Team)

**Q: How quickly should I respond to escalations?**
A: Escalations represent users who are waiting for help. Aim to review open escalations within the same business day. The user's chat session is locked until you resolve the escalation.

**Q: Can I see conversations from entities I am not mapped to?**
A: No. The dashboard is strictly scoped to your mapped entities. If you need access to another entity's data, ask your admin to update your Support Client Mapping.

**Q: What happens when I resolve an escalation?**
A: The linked chat session is unlocked (status changes from "escalated" back to "active"), and the user can resume chatting with the agent. Your resolution notes are saved for audit purposes.

**Q: How does the automated judge work?**
A: Every agent response is automatically scored by a separate AI model on three dimensions (completeness, grounding, actionability) out of 3 each, totalling 9. This happens asynchronously in the background — you do not need to trigger it. Responses scoring below 5 automatically appear in the Feedback Queue.

**Q: Can I change the judge scoring threshold?**
A: The judge model and whether it is enabled can be configured per entity in the Entity Settings page (under entity edit form). The threshold for what appears in the dashboard is set at the platform level.

**Q: What should I do if I see the same question failing repeatedly?**
A: This likely indicates a gap in the user guides. Check which guide files the agent searched (visible in the detail view) and whether they contain the answer. If not, update the relevant guide. Then use Re-test to verify the agent now answers correctly.

**Q: Can FM users see the judge scores or my resolution notes?**
A: No. Judge scores, resolution notes, and the review dashboard are only visible to support team members. FM users only see their own chat conversations and the thumbs up/down interface.

**Q: Does the re-test affect the original user's experience?**
A: No. Re-testing creates a completely separate session under your support account. The original user's conversation and session are untouched.

**Q: What is "Pending Engineering" status for?**
A: Use this when the issue cannot be fixed by updating guides alone — it requires a code change, bug fix, or new feature. This helps the engineering team track support-driven issues.
