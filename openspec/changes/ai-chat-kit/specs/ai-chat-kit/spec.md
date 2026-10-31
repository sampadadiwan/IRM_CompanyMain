# Spec Delta

## Purpose

The shared look and behaviour of CapHive's AI chat screens — the Assistants page, the KPI analysis
chat and every floating agent chat (including the LP chat and the Customer Support agent) — modelled
on the Support Console, so that users learn one chat rather than several.

## ADDED Requirements

### Requirement: Screens that use the shared chat
The Assistants page (Fund, Specific Fund, Portfolio, Portfolio Company and Capital Commitment
assistants), the KPI report analysis chat, and the floating chat window of every support agent with
chat turned on — including the LP assistant on the investor's dashboard and the Customer Support
agent — SHALL use the shared chat presentation described in this capability. The Support Console
SHALL use the same presentation with no visible change. FAQ threads, the mobile app and WhatsApp
SHALL be unchanged.

#### Scenario: Assistants page uses the shared chat
- **WHEN** a fund manager opens the Fund Assistant from the funds list
- **THEN** the page shows the conversation list, the thread and the question box of the shared chat

#### Scenario: LP chat uses the shared chat
- **WHEN** an investor opens "Need help?" on their dashboard
- **THEN** the window shows the shared chat's thread, question box and conversation list

#### Scenario: Support Console unchanged
- **WHEN** a support user opens the Support Console after this change
- **THEN** it looks and behaves as it did before this change

### Requirement: Conversation list
Each shared-chat screen SHALL list the current user's earlier conversations for the same assistant
and record that the screen showed before this change, newest first, grouped Today, Yesterday,
Previous 7 days and Older by when each last changed. Each row SHALL show the first question (without
quote marks it was pasted with) and, beneath it, the starter's name and the time (today) or the
locale-formatted date (earlier). The list SHALL offer New chat and a search that filters the rows.
Opening a row SHALL show that conversation without a full page reload and tint the row as open.
A conversation that was passed to a human SHALL show an "Escalated" badge in the warning colour.
When there are none, the list SHALL say "No conversations yet." The floating window SHALL open on the
latest conversation unless it has been idle more than 30 minutes, in which case it SHALL open on a new
conversation (the older one staying in the list); a question asked in a conversation the user opened
SHALL continue that conversation.

#### Scenario: Rows show question, who and when
- **WHEN** Priya opens the Specific Fund Assistant for a fund where she asked "Which LPs are overdue on Call 3?" today at 10:42
- **THEN** the list shows that question under "Today" with "Priya Sharma · 10:42" beneath it

#### Scenario: Older conversation shows a date
- **WHEN** a conversation last changed on 28 October 2026 and the user's locale is `en`
- **THEN** its row shows the date as 28/10/2026 under "Older"

#### Scenario: Only the user's own conversations
- **WHEN** an investor opens the LP chat
- **THEN** the list shows only conversations that investor started with the LP assistant

#### Scenario: Escalated conversation
- **WHEN** a Customer Support agent conversation has been passed to a human
- **THEN** its row shows an "Escalated" badge

#### Scenario: No conversations
- **WHEN** a user opens a shared-chat screen with no earlier conversations
- **THEN** the list says "No conversations yet."

#### Scenario: Idle conversation not continued by default
- **WHEN** a user opens the floating window and their latest conversation there was last active 2 hours ago
- **THEN** the window shows a new, empty conversation and lists the older one

#### Scenario: Reopened conversation continues
- **WHEN** a user opens an older conversation from the list and asks a question
- **THEN** the question is added to that conversation

### Requirement: Questions and answers
A question SHALL show as a grey bubble on the right. An answer SHALL show without a bubble or
avatar across the column, with tables in a bordered card that scrolls sideways when wide, quotes as
a callout, code blocks in a shaded panel, and underscores inside words left as written. Each answer
SHALL offer Copy and show its time. An answer SHALL show only the content that screen allowed before
this change: charts where the screen showed charts, and no remote images, scripts or page behaviours
on the Support Console.

#### Scenario: Table answer
- **WHEN** an answer contains a 3-column table of overdue LPs
- **THEN** the table sits in a bordered card and the question appears as a grey bubble above it

#### Scenario: Snake_case names
- **WHEN** an answer says "KMH_01 was created after KMH_01's calls"
- **THEN** the text shows no italics

#### Scenario: Copy an answer
- **WHEN** the user clicks Copy on an answer
- **THEN** the answer's text is copied and the button shows a tick briefly

### Requirement: Question box
Each shared-chat screen SHALL use the same question box: Enter sends, Shift+Enter starts a new
line, the box grows with its text, and a blank or whitespace-only question SHALL NOT be sent. While
an answer is being worked on the send button SHALL show a working state and a second question SHALL
NOT be sent from that screen. The box SHALL keep each screen's own extra: the Assistants page's
microphone, the KPI chat's document picker, and the Support Console's model choice and Stop.

#### Scenario: Enter sends
- **WHEN** Priya types "And on Call 4?" and presses Enter
- **THEN** the question appears in the thread and the box clears

#### Scenario: Blank question
- **WHEN** the user presses Enter in an empty box
- **THEN** nothing is sent

#### Scenario: Document picker kept
- **WHEN** a KPI report with a PDF document opens its analysis chat
- **THEN** the document picker shows beside the question box

### Requirement: Working and failed states
While an answer is being worked on, the thread SHALL show a "Thinking…" line under the question.
When an answer fails or times out, the thread SHALL show a "Not answered" note with the reason and
put the question back in the box.

#### Scenario: Thinking line
- **WHEN** a question has been sent and no answer has arrived
- **THEN** "Thinking…" shows under the question

#### Scenario: Provider unreachable
- **WHEN** the floating agent chat's AI service cannot be reached
- **THEN** the thread shows "Not answered" with "AI service is temporarily unreachable (network/DNS). Please try again shortly." and the question is back in the box

### Requirement: Suggested questions
An agent's suggested questions SHALL show as buttons in the empty thread. Clicking a suggestion's
text SHALL put it in the question box without sending; clicking its Ask button SHALL send it. Ask
SHALL be disabled while an answer is being worked on.

#### Scenario: Ask a suggestion
- **WHEN** Priya clicks Ask on "Show fill rate across deals" in the Portfolio Assistant agent window
- **THEN** that question is sent and appears in the thread

#### Scenario: Fill from a suggestion
- **WHEN** the user clicks the text of a suggestion
- **THEN** the question box holds that text and nothing is sent

### Requirement: Screen extras kept
The Assistants page SHALL keep its Export menu (AI Slides, Chat Slides, Export PowerPoint,
Efficiency Report) and hold-to-speak microphone, and Export PowerPoint SHALL include the
conversation's answers, tables and charts as before. The floating window SHALL keep its "Need help?"
bubble, drag, resize, maximise and close.

#### Scenario: Export PowerPoint after the change
- **WHEN** Priya exports a conversation with a table answer to PowerPoint
- **THEN** the file contains a slide with that table

#### Scenario: Maximise the floating window
- **WHEN** the user clicks Maximise in a floating agent window
- **THEN** the window widens and the conversation list shows beside the thread

### Requirement: Customer Support agent feedback and hand-off
Answers from the Customer Support agent, and only that agent, SHALL show 👍 and 👎. The chosen
rating SHALL show filled (👍 primary, 👎 danger) and be saved to the same feedback record and review
queue as before this change. Choosing 👎 SHALL open a note box; sending a note SHALL show "Thanks
for your feedback". Reopening a conversation SHALL show earlier ratings filled. A conversation the
assistant passes to a human SHALL still notify the CapHive support team as before.

#### Scenario: Rate down with a note
- **WHEN** Priya clicks 👎 on a Customer Support agent answer, types "Wrong fund" and clicks Send
- **THEN** 👎 shows filled, "Thanks for your feedback" shows, and the rating and note reach the CS feedback review queue

#### Scenario: Earlier rating shown
- **WHEN** Priya reopens a conversation in which she rated an answer 👍
- **THEN** that answer's 👍 shows filled

#### Scenario: Other agents have no rating
- **WHEN** a Portfolio Assistant agent answer is shown
- **THEN** it has no 👍 or 👎

### Requirement: One icon set and type scale
Shared-chat screens SHALL use Tabler icons only, one text size for questions, answers and tables,
regular weight, and theme colours only.

#### Scenario: No Font Awesome or Bootstrap Icons
- **WHEN** any shared-chat screen is shown
- **THEN** it contains no Font Awesome or Bootstrap Icons
