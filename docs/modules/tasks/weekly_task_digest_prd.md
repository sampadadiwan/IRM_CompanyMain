# PRD: Weekly Task Digest Email

Status: Approved to build — open questions resolved 2026-09-10
Scope: Phase 1 — `Investment Fund` entities only

## 1. Problem

Tasks live in the app (list, board, timeline) but nothing pushes a periodic summary
out. Today the only task email is `TasksMailer#send_notification`, fired per task on
create/update via `TaskNotifier`. That tells you a single task changed; it never tells
you where the week stands. Fund operations staff have to open the board and run three
separate filters (`Overdue`, `Due Next Week`, completed) to get that picture.

## 2. Goal

Every Friday, email each opted-in fund employee one digest, led by a summary stat band
and followed by three sections:

1. **Done this week** — closed since the start of the current week.
2. **Due next week** — open tasks whose due date falls in next week.
3. **Delayed** — open tasks overdue within the last 90 days.

Non-goal for phase 1: changing anything about how tasks are created, assigned or
displayed in the app.

## 3. Audience and gating

Three conditions, all required:

| Condition | Implementation |
| --- | --- |
| Entity is a fund | `Entity.funds` (`EntityScopes` → `where(entity_type: "Investment Fund")`) |
| Digest enabled for the entity | new `entity_settings.weekly_task_digest_enabled` boolean, default `false` |
| User opted in | `entity.employees.active.with_tag("Tasks")` |

`Angel Fund` is deliberately excluded even though `Entity#fund?` accepts it. Phase 2
can widen the scope to `Entity#fund?` once the format has been validated on one type.

`employees` is `has_many :employees, class_name: "User"`, and `User` is
`acts_as_paranoid` through `Trackable`, so soft-deleted users are already excluded.
`.active` additionally drops deactivated accounts.

### 3.1 The tag

This reuses the existing free-text `users.tag_list` convention, exactly like
`entity.employees.with_tag('Kpi')` in `KpiReport` and
`.with_tag('db_dump_notification')` in `EntityDbDumpJob`.

Two changes go with it:

- Add `"Tasks"` to `User::NOTIFICATION_TAGS` so it appears in the datalist on the user
  form (`users/_form.html.erb`), and extend the comment above that constant that
  documents which tags are matched by exact string elsewhere.
- **Known sharp edge:** `User.with_tag` is `tag_list LIKE '%Tasks%'`. A user tagged
  `Subtasks` or `Tasks-Weekly` also matches. `Kpi` has the same weakness today and it
  has not bitten anyone. **Decided: keep `Tasks` and accept the substring match**, for
  consistency with the existing tags rather than introducing a second, stricter matcher
  for one feature. Recorded here so the behaviour is a choice, not a surprise.

## 4. What each recipient sees

**Decided: scope the digest through `TaskPolicy::Scope` per recipient**, not a flat
entity-wide query. This makes the email agree with the app for free:

- A `company_admin` sees every non-support task on the entity — a genuine fund-wide
  weekly view.
- An `employee` sees tasks assigned to them plus deal and deal-investor tasks — their
  own week, which is what an individual contributor wants anyway.

Every deep link in the mail therefore opens for the person who received it, and no row
in the email is a task they cannot view in the app.

`for_support` tasks are already excluded by the policy scope for non-support users.

### 4.1 Tasks logged by another entity

Tasks whose `for_entity_id` points at this fund **are included**. No special-casing is
needed: `TaskPolicy::Scope` already resolves `entity_id = ? OR for_entity_id = ?` for
company admins and support users, so an admin's digest picks them up automatically.

The employee branch of that scope matches on `entity_id` alone, so an employee's digest
covers tasks assigned to them plus deal and deal-investor tasks on their own entity.
That asymmetry is the policy's existing behaviour and the digest inherits it
deliberately. Widening it would be a change to `TaskPolicy`, which would also change the
in-app task list. Out of scope here.

## 5. Date windows

Reuse `Task.due_filter_range` and the existing scopes rather than reimplementing week
maths. All boundaries follow Rails' locale-configured start of week, same as the board
filters, so the email and the UI can never disagree.

| Section | Definition | Source |
| --- | --- | --- |
| Done this week | `completed = true AND completed_on IN today.all_week` | `completed` scope + `all_week` |
| Due next week | `completed = false AND due_date IN (today + 1.week).all_week` | `Task.due_filter_range("next_week")` |
| Delayed | `completed = false AND due_date IN (today - 90.days)...today` | `Task.delayed`, bounded — §5.1 |

Tasks with no due date appear in no section. That is intentional — a digest of undated
tasks is a backlog dump, not a weekly plan.

Overlap is impossible by construction: delayed and due-next-week are disjoint ranges,
and both are `incomplete` while section one is `completed`.

### 5.1 Delayed window

**Decided: the delayed section reaches back 90 days, not forever.** A fund with years of
abandoned tasks would otherwise open its digest onto a section nobody reads, and the
whole point of the email is that it is actionable.

```ruby
DELAYED_WINDOW = 90.days
# incomplete tasks due in the last 90 days, up to yesterday
scope.incomplete.where(due_date: DELAYED_WINDOW.ago.to_date...Time.zone.today)
```

Put this constant on the `WeeklyTaskDigest` service, **not** on `Task`. The existing
`Task.delayed` scope and `Task#delayed?` drive the "Delayed" badge on the list row and
the board card, and both must keep meaning "overdue at all". Narrowing them would
silently change the UI.

Consequence to accept: a task more than 90 days overdue drops out of the digest
entirely. It stays visible in the app under the `Overdue` filter, and the section header
links straight there (§7.4), so nothing becomes unreachable — it is just no longer
pushed weekly. The row cap in §7.4 applies on top of this window.

### 5.2 Send day

**Decided: send Friday**, so "done this week" is the week just worked and "due next
week" is the week being planned. That makes "done this week" a partial week:
anything closed Friday evening, Saturday or Sunday lands in the following digest rather
than this one. Accepted as the cost of planning-oriented timing.

## 6. Delivery mechanics

### 6.1 Job

`WeeklyTaskDigestJob < ApplicationJob`, registered in `config/initializers/sidekiq.rb`
alongside the other cron jobs:

```ruby
Sidekiq::Cron::Job.create(name: 'WeeklyTaskDigestJob', cron: '30 11 * * 5', class: 'WeeklyTaskDigestJob')
```

**Timezone caveat:** app servers run UTC. `config.time_zone` is `'New Delhi'`, which sets
`Time.zone` inside Rails but not the box clock — see the `sidekiq_restart_at` comment in
`config/schedule.rb`, which works around the same thing. The cron expression must be
written in UTC for the intended local send time, and the `us` region variant needs a
different hour, exactly as the daily Sidekiq restart already handles it.

Structure follows `EntityDbDumpJob`: iterate with `find_each`, wrap each entity in its
own `rescue StandardError` so one fund's failure cannot abort the batch, log and
`ExceptionNotifier.notify_exception` per failure.

```
WeeklyTaskDigestJob
  Entity.funds.joins(:entity_setting)
        .where(entity_settings: { weekly_task_digest_enabled: true }).find_each
    entity.employees.active.with_tag("Tasks").find_each
      digest = WeeklyTaskDigest.new(user, entity, as_of: Time.zone.today).call
      next if digest.empty?
      TaskDigestMailer.with(user_id:, entity_id:, as_of:).weekly_digest.deliver_later
```

Put the query logic in a `WeeklyTaskDigest` service object
(`app/packs/core/tasks/services/`), not in the mailer. It keeps the buckets and the
stats testable without rendering, and matches where `TaskList` and `ImportTaskService`
already live in the pack.

### 6.2 Notifier and mailer

The digest is raised as a **Noticed event**, `WeeklyTaskDigestNotifier < BaseNotifier`,
not by calling the mailer directly. That is how the rest of the app's outgoing mail
works, and it is what earns the digest four things a bare mailer call does not get:

- a `Noticed::Notification` row, so the digest appears in the in-app bell and in the
  notifications report alongside every other message
- SES bounce and complaint correlation, via `ApplicationMailer#tag_for_bounce_tracking`
  and the `X-CapHive-Tracking-Id` header, which is only applied when `@notification`
  is present
- the per-entity send delay (`entity_setting.email_delay_seconds`), which is what keeps
  a fund-wide Friday burst from tripping SES rate limits
- the recipient email/WhatsApp toggles in `BaseNotifier`'s `deliver_by` conditions

**`record` is the recipient, not a task.** A digest has no single subject row, and
`NotificationExtensions#email_enabled` dereferences `model.entity_id` — which `Entity`
does not have and `User` does. Using the recipient makes that check trivially true
(a fund employee is always allowed their own entity's mail) and gives the in-app
notification a sensible owner. The three section counts ride along in `params` so
`#message` can render the bell text without rebuilding the digest.

`custom_notification` returns nil: the body is a rendered report, not client
boilerplate. Per `NotificationExtensions`, that keeps the email condition true and the
WhatsApp condition false, so no WhatsApp message is attempted.

The mailer itself is `TaskDigestMailer < ApplicationMailer`, `weekly_digest` action,
view at `app/packs/core/tasks/views/task_digest_mailer/weekly_digest.html.erb`. It takes
`user_id:` and `entity_id:` params rather than `mail(to: ...)` with a raw address list,
so `ApplicationMailer#setup_defaults` handles from-address resolution, CC, reply-to and
sandbox redirection (`entity_setting.sandbox` → `sandbox_emails`) with no extra code.
`CashFlowReminderMailer` bypasses that because its recipients are free-text config
strings; here they are real `User` records, so the standard path applies.

Subject, leading with the number that decides whether the mail gets opened:

- `Weekly Tasks — 7 delayed, 12 due next week — Alpha Fund I`
- `Weekly Tasks — all on track, 12 due next week — Alpha Fund I` (when nothing is delayed)

**Dates in the body use bare `l(task.due_date)` / `l(task.completed_on)`.** Per
CLAUDE.md, `EmailDateLocalization` overrides `l` in the mailer view context and renders
`%b %d, %Y` with `locale: :en` forced. Never `strftime`, never a bare
`<%= task.due_date %>` — Rails 8 prints ISO for that.

Ship a `weekly_digest.text.erb` alongside the HTML. A digest that is HTML-only is a
deliverability liability, and the plain-text part is a five-line loop over the same
three buckets.

### 6.3 Empty digests

If all three sections are empty, skip the send. A recurring "you have nothing" email is
the fastest way to train people to filter the sender.

A recipient with completed work but nothing due or delayed still gets a mail. That is a
good-news digest and it should send. Only the all-empty case is suppressed.

## 7. Email design

The house style for rich transactional email already exists:
`SupportAgentEmailHelper` (`app/packs/ai/support_agents/helpers/`) provides a colour
palette and Outlook-safe table-based building blocks — `sa_banner`, `sa_badge`,
`sa_section`, `sa_callout`, `sa_th` / `sa_td`, `sa_kv_table`, `sa_cta`, `sa_footer`,
`sa_intro`. The digest uses these rather than inventing a second visual language.

**Packaging:** `core` declares its dependencies as `app/packs/core` only, so a core
mailer reaching into the `ai` pack for its helper is a boundary violation. Promote the
module to `app/packs/core/base/helpers/email_style_helper.rb` — beside
`EmailDateLocalization`, which mailers already depend on — and leave
`SupportAgentEmailHelper` as `include EmailStyleHelper` plus its agent-specific
`sa_tone_for`. Pure move, no behaviour change, and both mailer families then share one
palette.

Its palette maps one-to-one onto the four colours the in-app stat cards already use
(`tasks/_stats.html.erb`: success, warning, danger, info), so the email and the dashboard
read as the same product.

### 7.1 A lighter variant

The solid `sa_*` builders fill every block with saturated colour and box every table
cell in a full grid. At digest length — three tables, up to 15 rows each — that reads
as heavy and makes the message look like a system report rather than a summary.

So the digest uses a **light variant** added alongside them: `sa_light_banner`,
`sa_light_section`, `sa_light_th` / `sa_light_td`, `sa_soft_badge`, `sa_light_cta`,
`sa_light_footer`, plus the retuned `sa_stat_tiles` and `sa_note`. These draw with
hairlines and white space instead of fills and grids. Two new palettes back them:
`SA_LIGHT` (the same hues at lower saturation, with barely-there tints) and
`SA_NEUTRAL` (a four-step type hierarchy — ink, body, muted, faint — plus two rule
weights).

Opt-in by design. The solid builders are untouched, so nothing changed for the twelve
existing agent and fund mailer views. If the team likes this treatment, those can adopt
it one at a time.

### 7.2 Layout

```
┌──────────────────────────────────────────────────────────┐
│ WEEKLY TASKS                    ← sa_light_banner        │
│ 6 delayed                         (tone by state)        │
│ Week of Sep 07 – Sep 13, 2026 · Ace Fund                 │
│ ──────────────────────────────────────────────────────── │
│  ┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐            │
│  │   2    │ │   3    │ │   6    │ │   12   │  ← stat band│
│  │  DONE  │ │DUE NEXT│ │DELAYED │ │  OPEN  │   (white,   │
│  │THIS WK │ │  WEEK  │ │        │ │ TOTAL  │   hairline) │
│  └────────┘ └────────┘ └────────┘ └────────┘            │
│  2 more than last week · oldest delayed 87 days          │
│                                                          │
│ Delayed 6                                 View all →     │
│ TASK                              DUE          LATE      │
│ ──────────────────────────────────────────────────────── │
│ File SEBI Quarterly report        Aug 21, 2026  21 days  │
│ FM1 Ace                                                  │
│ │ Auditor has the draft. Waiting on sign-off.            │
│ ──────────────────────────────────────────────────────── │
│ Due next week 3                           View all →     │
│ Done this week 2                          View all →     │
│                                                          │
│ [ Open task board → ]           ← sa_light_cta           │
│ You receive this because you are tagged "Tasks" on …     │
└──────────────────────────────────────────────────────────┘
```

Delayed comes **first**. It is the only section that needs action today; the done
section is the reward and belongs at the bottom.

### 7.3 The stat band

Four tiles, white with a hairline, mirroring the in-app cards. The number carries the
colour; the label is small uppercase grey.

| Tile | Value | Tone |
| --- | --- | --- |
| Done this week | count of section 1 | `:success` |
| Due next week | count of section 2 | `:info` |
| Delayed | count of section 3 | `:danger`, or `:muted` at zero |
| Open total | all incomplete tasks in the policy scope | `:warning` |

"Open total" is the denominator. Without it, "6 delayed" reads very differently on a
fund with 12 open tasks than on one with 300.

Beneath the tiles, one muted centred line of derived stats:

- **Week-over-week completion delta** — `2 more than last week` / `4 fewer than last
  week` / `same as last week`. The single most motivating number in a weekly digest,
  and it costs one extra `SUM(CASE …)` in the same pass.
- **Age of the oldest delayed task** — `oldest delayed 87 days`. Turns a flat count
  into a sense of drift. Omitted when nothing is delayed.
- **Assignee spread** — `across 5 assignees`, for recipients whose scope is fund-wide.

The banner tone is driven by the delayed count, so the email is colour-coded before a
single number is read:

| Delayed | Tone | Headline |
| --- | --- | --- |
| 0 | `:success` | `All on track` |
| 1–5 | `:warning` | `5 delayed` |
| 6+ | `:danger` | `6 delayed` |

### 7.4 Rows: three columns, three lines

| Section | Columns |
| --- | --- |
| Delayed | Task, Due, Late (`sa_soft_badge` in `:danger`) |
| Due next week | Task, Due |
| Done this week | Task, Done |

The owner and the assignee are **not columns**. At email width a five-column table
wrapped every title across three lines; as a metadata line under the title they cost no
width at all. Each row is therefore three lines of decreasing weight:

1. **Title** — `Task#display_details`, truncated to 90 characters, linked to
   `task_path(id:, sub_domain:)`. `display_details` is the right accessor: it already
   falls back to the legacy pre-ActionText column, so tasks created years ago do not
   render blank.
2. **Metadata** — `Task#owner_display_name` and the assignee, joined by a middot.
3. **Note** — the task's `response` field, which is what the task form labels
   "Response" and what fund users actually keep their running commentary in. Rendered
   as a quiet quote-ruled line, truncated to 140 characters, omitted entirely when the
   task has none. A delayed row that says *why* it slipped is worth far more than one
   that only says it did.

The note needs `rich_text_response` preloaded, which `TaskList` deliberately does not
load. That divergence is intentional and commented in both places: the list views do
not show the response, the digest row does. `Task#display_response` mirrors
`display_details`, including the legacy-column fallback.

**Row cap: 15 per section**, then a muted `5 more tasks not shown` link. An unbounded
table is both an unreadable email and an unbounded render.

Section header links carry **absolute dates**, so a reader who clicks "View all" lands
on the same set rather than a near miss. Not `due_filter=next_week`: that key looks
tidier and pre-selects the dropdown, but `Task.due_filter_range` resolves it against
`Time.zone.today` when the link is opened. The digest goes out Friday, so a Monday
click would land on the following week — disjoint from the rows and the count printed
beside the link. An empty section
renders a single muted line rather than vanishing — a missing section reads as a broken
email, `Nothing due next week.` reads as a clean week.

### 7.5 Rendering constraints

- Every colour is set inline on the element. Mail clients strip `<style>` blocks
  unpredictably, and the `sa_*` helpers already inline everything.
- Set an explicit background on the tiles and table cells. Several clients apply their
  own dark-mode inversion, and a tile with a coloured foreground on a transparent
  ground can end up unreadable.
- The `mailer` layout already constrains width; no new layout is needed.
- No web fonts, no images, no external CSS. The digest must render identically with
  images blocked, which is the default in most corporate mail clients.

## 8. Query hygiene

Per CLAUDE.md, and because `tasks` grows steadily on multi-fund tenants:

- **Compute every stat in one aggregate pass**, in the style of `Task.stat_counts` —
  add a `Task.digest_counts(scope, as_of:)` returning completed-this-week,
  completed-last-week, due-next-week, delayed, open-total and `MIN(due_date)` among
  delayed rows. Six numbers, one query, no relation loaded.
- Follow `stat_counts`' existing shape: `SUM(CASE WHEN … END)` with
  `sanitize_sql_array`, and `reorder(nil)` before `pick`. Not `FILTER`, not
  engine-specific boolean syntax — the same SQL has to run on MySQL in production and
  SQLite under Cucumber.
- **Do not compute "days late" in SQL.** `DATEDIFF` is MySQL, `julianday` is SQLite;
  the pair silently diverges. Return `MIN(due_date)` and subtract in Ruby.
- Never call `blank?`/`present?` on the bucket relations to decide whether to send.
  Branch on the integers from `digest_counts`, which are already in hand.
- Preload only what the email renders: `includes(:assigned_to, :owner, :rich_text_details)`.
  The row shows the task text, the owner label and the assignee. Do not preload
  `task_template`, `for_entity`, `user` or `rich_text_response` — `TaskList`
  deliberately dropped those for exactly this reason.
- Apply the 15-row cap as a SQL `LIMIT`, ordered by `due_date` (`completed_on` for
  section one). The "+N more" count comes from `digest_counts`, not from loading the
  remainder.
- Iterate entities and recipients with `find_each`.

### 8.1 Missing index

`tasks` currently indexes `entity_id`, `status`, `owner` and the various foreign keys.
**There is no index on `due_date` or `completed_on`.** Every section and every stat
filters on one of them alongside `entity_id` and `completed`. Add before rollout:

```ruby
add_index :tasks, [:entity_id, :completed, :due_date]
add_index :tasks, [:entity_id, :completed_on]
```

These also speed up the existing board and list due-date filters and `Task.stat_counts`,
which scan the same columns today with no index behind them.

## 9. Configuration surface

| Setting | Where | Default |
| --- | --- | --- |
| `weekly_task_digest_enabled` | `entity_settings`, entity settings form | `false` |
| Recipient opt-in | `users.tag_list` contains `Tasks`, on the user form | none |

Deliberately **not** configurable in phase 1: send day, send time, section selection,
row cap, per-user frequency. Every one is a column, a form field and a branch, and none
has a demonstrated requirement. `kpi_reminder_frequency` and `kpi_reminder_before` are
the precedent if per-entity scheduling is needed later.

## 10. Testing

Cucumber only, no RSpec — `features/core/weekly_task_digest.feature`, steps in
`features/step_definitions/`. Scenarios:

- A fund entity with a tagged, active employee receives a digest containing a task
  done this week, one due next week and one overdue.
- A non-fund entity (`Company`, `Angel Fund`) sends nothing.
- An employee without the `Tasks` tag receives nothing.
- An inactive employee receives nothing.
- An entity with the setting off sends nothing even with tagged employees.
- All three sections empty → no email sent.
- Completed work but nothing open → email still sent.
- An employee (non-admin) sees only their policy-scoped tasks, not a colleague's.
- A task overdue by 120 days is absent from the delayed section; one overdue by 60 days
  is present.
- A task with no due date appears in no section.
- The stat band's four numbers match the rows rendered beneath them.
- A section with 20 matching tasks renders 15 rows plus a `+ 5 more` link.
- Dates in the rendered body read `Sep 11, 2026`, not `11/09/2026` — the regression
  guard for the `EmailDateLocalization` contract.

Cucumber needs local Redis on 6379 for fund-creating scenarios, and runs should be
prefixed with a random `TEST_ENV_NUMBER`.

## 11. Rollout

1. Migration (two indexes + `weekly_task_digest_enabled`), shipped and deployed alone.
2. Promote `SupportAgentEmailHelper` to `EmailStyleHelper` in core, add `sa_stat_tiles`.
3. Service, job and mailer. Cron registered, setting default `false` — nothing sends.
4. Enable for one internal fund entity, review the real email in a real client.
5. Enable per customer on request.

Three rake tasks in `lib/tasks/task_digest.rake` make step 4 possible without waiting
for Friday:

| Task | Effect |
| --- | --- |
| `task_digest:preview[user_id,as_of]` | Renders to `tmp/`. Sends nothing, writes nothing. |
| `task_digest:deliver[user_id,as_of]` | Really sends, to one user, in-process. |
| `task_digest:run[entity_id,as_of,now]` | Really sends to every tagged recipient. Queued unless `now=true`. |

`deliver` cannot simply call the notifier and wait. Noticed 3 aliases `deliver` to
`deliver_later` — both always enqueue `Noticed::EventJob`, which in turn enqueues the
mailer — so on a box with no Sidekiq worker the notification row appears and the email
never does. The task therefore creates the notification with `enqueue_job: false` and
then invokes the mailer with the same params `Noticed::DeliveryMethods::Email` would
have passed it. `run` without `now=true` takes the real queued path and warns when no
Sidekiq process is running.

What "really sends" means is the environment's decision: development uses
`letter_opener` (opens in a browser, never leaves the machine) with `sanitize_email`
rewriting the recipient, while staging and production go out over SES.

## 12. Resolved decisions

Settled 2026-09-10; recorded so the reasoning survives the review.

| # | Question | Decision |
| --- | --- | --- |
| 1 | Send day | **Friday.** Planning next week beats a complete record of last week. |
| 2 | Per-recipient or entity-wide | **Per recipient**, scoped through `TaskPolicy::Scope` (§4). |
| 3 | Delayed section depth | **Last 90 days** (§5.1), capped at 15 rows with a link to the full filter. |
| 4 | Include `for_entity_id` tasks | **Yes** — falls out of the policy scope for admins (§4.1). |
| 5 | Tag name | **Keep `Tasks`**, substring match accepted (§3.1). |

## 13. Phase 2 candidates

- Extend to `Angel Fund`, or to all of `Entity#fund?`.
- A per-assignee breakdown table for admins, showing open and delayed counts by person.
- A sparkline or bar of completed-per-week over the last 8 weeks in the stat band.
- Per-user opt-out link in the footer, rather than an admin removing the tag.
- Recurrence-aware grouping, so a daily recurring task does not fill the delayed
  section with five near-identical rows.
- WhatsApp summary for entities with `whatsapp_enabled` users.
