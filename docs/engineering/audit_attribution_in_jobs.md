# Audit attribution: carrying the acting user into background jobs

Every model in this app is audited — `Trackable` applies
`audited(on: %i[create update destroy])` alongside `acts_as_paranoid`. But until this
change, most audit rows recorded **no actor**, because the acting user never crossed
the boundary from the web process into Sidekiq.

This document explains what was broken, how `audited` picks the user, what
`ActiveSupport::CurrentAttributes` is, and how the two are now joined up.

## 1. The problem: 74% of the audit trail said "System"

Measured against the production data copy — 439,484 audit rows, split by action and by
whether the audit was written inside an HTTP request or inside a job:

| action  | origin       | with user | no user     | unattributed |
|---------|--------------|-----------|-------------|--------------|
| create  | in a job     | 48,470    | 108,109     | **69.0%**    |
| create  | in a request | 13,676    | 105         | 0.8%         |
| destroy | in a job     | 6,101     | 32,613      | **84.2%**    |
| destroy | in a request | 8,841     | 1,513       | 14.6%        |
| update  | in a job     | 11,492    | **183,891** | **94.1%**    |
| update  | in a request | 24,222    | 451         | 1.8%         |

**324,613 of 439,484 rows — 74% of the entire audit trail — recorded no actor.**

The in-request path was already fine (0.8–1.8% unattributed). The job path was the whole
story, and *updates* were the worst case: imports (`import_capital_commitment`,
`import_portfolio_investment`, `import_capital_remittance`, …) and the recalculation jobs
account for 183,891 unattributed rows on their own.

This is not cosmetic. The audit trail is a compliance artifact for a fund-administration
system. "System" against a capital-commitment change is not a neutral default — it is a
missing answer to "who did this?", missing for three quarters of the record.

### How "origin" was determined

Not by `request_uuid`. That column looks like a request marker but is not one — `audited`
does `self.request_uuid ||= SecureRandom.uuid` (`audited/audit.rb:195`), so it is *always*
populated, including outside a request, and proves nothing. The honest discriminator is
**`remote_address`**, which only `Audited::Sweeper` sets and only from a live request:

```sql
SELECT action,
       CASE WHEN remote_address IS NOT NULL AND remote_address <> ''
            THEN 'in a request' ELSE 'in a job' END AS origin,
       SUM(user_id IS NOT NULL) AS with_user,
       SUM(user_id IS NULL)     AS no_user
FROM audits GROUP BY action, origin;
```

## 2. How `audited` decides who did it

Every audit row gets its user from exactly one place — `set_audit_user`, a
`before_create` callback in `audited/audit.rb:187`:

```ruby
def set_audit_user
  self.user ||= ::Audited.store[:audited_user]              # set by .as_user { }
  self.user ||= ::Audited.store[:current_user].try!(:call)  # set by the Sweeper
  nil
end
```

Two keys, one store. `Audited.store` is **thread-local**. That single fact is the entire
problem.

In a request, `Audited::Sweeper#around` runs as an `around_action` and fills the store
from the controller (`audited/sweeper.rb:12`), including a lambda that calls
`Audited.current_user_method` — configured here as `:current_user_or_support_user`
(`config/initializers/audited.rb:1`, implemented in `WithAuthentication`, so that support
staff impersonating a user are logged as the support user).

In a job there is no controller, so no Sweeper runs, so the store is empty:

```
── WEB REQUEST (Puma thread) ────────────────────────────────────────────
  DELETE /funds/319
       │
       ▼
  Audited::Sweeper#around ──writes──▶ Audited.store[:current_user] = -> { … }
       │                               ▲
       ▼                               │ same thread ⇒ store is visible
  fund.destroy                         │
       │                               │
       ▼                               │
  set_audit_user ──────reads───────────┘
       │
       ▼
  audits row: user_id = 42   ✅


── BACKGROUND JOB (Sidekiq thread, separate process) ────────────────────
  funds_controller.rb:162
  FundDeleteAllJob.perform_later(@fund.id, klass, current_user.id)
       │                                         └── the user IS known here,
       │                                             and was used only for
       ▼                                             send_notification
  ╔═══ process / thread boundary ═══╗
  ║  Audited.store is EMPTY here     ║  ← no controller ⇒ no Sweeper
  ╚══════════════════════════════════╝
       │
       ▼
  fund.destroy   (cascades through thousands of rows)
       │
       ▼
  set_audit_user ──reads──▶ store[:audited_user] = nil
                            store[:current_user] = nil
       │
       ▼
  audits row: user_id = NULL   ❌  → the UI shows "System"
```

The user was never unknown. It was known and discarded.

### The pre-existing partial fix

`audited` already offers the hook: `Audited.audit_class.as_user(user) { … }` writes the
*first* store key, which `set_audit_user` reads before anything else:

```ruby
def self.as_user(user)          # audited/audit.rb:140
  last = ::Audited.store[:audited_user]
  ::Audited.store[:audited_user] = user
  yield
ensure
  ::Audited.store[:audited_user] = last
end
```

`BulkActionJob` already did this, which is why bulk actions were attributed. About a dozen
other files did it by hand. The problem was that it is **opt-in per job** — nine
delete-capable jobs never called it, and every new job started out unattributed with
nothing to catch the omission.

## 3. `ActiveSupport::CurrentAttributes` in detail

`CurrentAttributes` is Rails' supported way to hold per-execution-context state: values
that belong to "whatever is running right now" rather than to any particular object. You
subclass it and declare attributes:

```ruby
class Current < ActiveSupport::CurrentAttributes
  attribute :user
end

Current.user = some_user
Current.user  # => some_user
```

### It is not a global variable

The class-level accessors are a façade. `Current.user` is `method_missing` forwarding to
`Current.instance.user` (`current_attributes.rb:178`), and `instance` is:

```ruby
def instance
  current_instances[current_instances_key] ||= new     # :101
end

def current_instances
  ExecutionContext.current_attributes_instances        # :170
end
```

`ExecutionContext` is backed by `ActiveSupport::IsolatedExecutionState`, which stores per
**thread** or per **fiber** depending on `config.active_support.isolation_level`. So each
Puma thread and each Sidekiq thread sees its own `Current` instance. Two concurrent
requests cannot see each other's user. This is the same isolation `Audited.store` uses —
which is precisely why neither survives a hop into another process.

### The reset lifecycle is Rails', not ours

The dangerous failure mode for ambient state is *leakage*: thread pools reuse threads, so
a value left behind by request A can be read by request B — and for an audit trail, a
**wrong** name is far worse than a blank one.

Rails closes that hole itself. `activesupport/railtie.rb` registers:

```ruby
app.executor.to_run      { … ActiveSupport::CurrentAttributes.clear_all … }   # :51
app.executor.to_complete { … ActiveSupport::CurrentAttributes.clear_all … }   # :61
```

`clear_all` resets every instance and empties the registry (`current_attributes.rb:158`).
Because ActiveJob wraps every perform in `app.reloader.wrap`
(`activejob/railtie.rb:82-85`), and the reloader runs executor callbacks, **`Current` is
cleared before and after every request and every ActiveJob job**. We do not have to police
this, and the probe in §7 confirms it empirically.

The one gap: code that runs *outside* the executor. In this app that means the three
workers that `include Sidekiq::Worker` directly rather than inheriting `ApplicationJob`
(see §6).

### The API worth knowing

- `Current.user = x` — set for the rest of this execution context.
- `Current.set(user: x) { … }` — set **for the block only**, restoring the previous value
  afterwards (`current_attributes.rb:223`, which delegates to `with`). Prefer this
  wherever the scope is known; it cannot leak even if the executor does not run.
- `Current.reset` — restore declared defaults.
- `Current.attribute :foo` — declare; also generates instance accessors.
- `Current.resets { … }` / `before_reset` — callbacks when the context ends.
- In tests, `ActiveSupport::CurrentAttributes::TestHelper` resets between cases; Rails
  includes it automatically when `executor_around_test_case` is on.

### The honest criticisms

`CurrentAttributes` is global mutable state wearing a nice hat, and the objections are
real:

1. **Invisible dependencies.** A method that reads `Current.user` does not say so in its
   signature. You cannot tell from a call site what it needs.
2. **Test order sensitivity.** Anything reading ambient state can pass alone and fail in a
   suite, or vice versa.
3. **Scope creep.** This is the big one. `Current` starts with the actor and accretes
   `Current.entity`, `Current.fund`, `Current.locale` until it is a god object whose
   contents nobody can predict, and every one of those becomes an implicit argument to
   half the codebase.

**The rule for this codebase: `Current` holds the actor and nothing else.** If you want to
add an attribute, pass it as an argument instead. The justification for `Current.user` is
narrow and specific — attribution is genuinely ambient (it applies to every write made
anywhere in the call stack, which is exactly what you cannot thread through as a
parameter), and `audited` already models it that way with its own thread-local store. That
argument does not generalise to the next attribute someone wants to add.

## 4. The design

Three small pieces.

**`app/packs/core/base/models/current.rb`** — the declaration, holding one attribute:

```ruby
class Current < ActiveSupport::CurrentAttributes
  attribute :user
end
```

**`WithAuthentication`** — publish the actor during a request, after `authenticate_user!`
so `current_user` is resolved. It deliberately uses the *same* value the Sweeper uses, so
the two paths cannot disagree about who acted when support staff are impersonating:

```ruby
before_action :set_current_user

def set_current_user
  Current.user = current_user_or_support_user
end
```

**`ApplicationJob`** — carry it across the process boundary, and hand it to `audited`:

```ruby
def serialize
  super.merge("acting_user_id" => Current.user&.id)
end

def deserialize(job_data)
  super
  @acting_user_id = job_data["acting_user_id"]
end

around_perform do |job, block|
  user = job.acting_user

  if user
    Current.set(user: user) { Audited.audit_class.as_user(user) { block.call } }
  else
    block.call
  end
end

def acting_user
  return @acting_user if defined?(@acting_user)

  @acting_user = if @acting_user_id
                   User.with_deleted.find_by(id: @acting_user_id)
                 else
                   Current.user
                 end
end
```

```
── WITH THE FIX ─────────────────────────────────────────────────────────
  controller ── perform_later ──▶ serialize adds "acting_user_id" => 42
                                         │
  ╔═══ process boundary ═══╗              │
       │                                  ▼
       ▼                    ApplicationJob#around_perform
  FundDeleteAllJob#perform ◀── wrapped in ──▶ Audited.audit_class.as_user(user)
       │                                             │
       ▼                                             ▼
  fund.destroy                         Audited.store[:audited_user] = user
       │                                             │
       ▼                                             │
  set_audit_user ────────reads────────────────────────┘
       │
       ▼
  audits row: user_id = 42   ✅
```

Because `around_perform` also sets `Current.user`, a job that enqueues another job
propagates the same actor down the chain — 19 job files call `perform_later`, so this
matters.

Every job inherits this from `ApplicationJob`. The nine delete-capable jobs that never
called `as_user` needed **no edit**. The dozen existing manual `as_user` calls are now
redundant but harmless: `set_audit_user` uses `||=`, and `as_user` restores the previous
value on exit, so an inner block simply wins for its own scope.

## 5. Traps this design deliberately avoids

**The `discard_on` × `acts_as_paranoid` trap.** `ApplicationJob` sets
`discard_on ActiveJob::DeserializationError`, and `User` is `acts_as_paranoid` via
`Trackable`. If the actor were serialized as a **GlobalID to the User record**, then a job
enqueued by someone who is later deactivated would raise on deserialize and be **silently
discarded** — losing real work, not merely the attribution. The id therefore travels as a
plain `Integer`, and is resolved with `User.with_deleted.find_by(id:)`, which returns `nil`
rather than raising, and which also means a since-deactivated user still attributes to
their own name.

**Guessing the actor from job arguments.** Tempting, since many jobs already take a
`user_id` — but at different positions (`FundDeleteAllJob` 3rd, `BulkActionJob` 2nd) and
sometimes meaning the *recipient* of a notification rather than the actor. A wrong guess
writes a false statement about a person into a compliance record. Rejected.

**Inventing a "system" actor when none is known.** Also rejected, for the same reason:
an honest `NULL` is better than a plausible fiction. See §6 for the alternative.

## 6. What this does not fix

- **Three workers bypass ActiveJob** and so never run `around_perform`:
  `core/users/jobs/deployment_notification_worker.rb`,
  `ai/support_agents/jobs/agent_scheduler/scheduler_polling_job.rb`,
  `ai/support_agents/jobs/agent_scheduler/agent_runner_job.rb`. They `include
  Sidekiq::Worker` directly. Covering them needs Sidekiq client/server middleware, and they
  are also the only code here outside the executor's `clear_all` guarantee.
- **`sidekiq-cron` runs have no originating human.** They stay unattributed, correctly. If
  we want them to read as something better than "System", the fix is a designated system
  user record, not a guess.
- **1,513 in-request destroys are still unattributed** (14.6% of in-request destroys).
  That is a separate bug in the request path — likely `current_user_or_support_user`
  returning `nil`, or unauthenticated signed-id flows — and is not addressed here.
- **Nothing is backfilled.** The 324,613 existing `NULL` rows stay `NULL`; that
  information is gone. Expect a visible discontinuity at the deploy date in anything that
  reports on "System" activity.

## 7. Verification

The mechanism was verified end to end by writing a real `Audit` row from inside a job,
exercising `audited`'s own `set_audit_user` callback:

```
1) enqueued with NO acting user (today's behaviour):
     inside perform: Audited.store[:audited_user] = nil
     audit written  : user_id=nil

2) enqueued from a request that had a user (the fix):
     serialized payload acting_user_id = 1
     Current.user after reset = nil          ← proves perform is not reading
     inside perform: Audited.store[:audited_user] = #<User id: 1 …>   leftover thread state
     audit written  : user_id=1  Emp1

3) nested: a job enqueued from inside an attributed job inherits the actor:
     inner job's payload acting_user_id = 1
```

To check the effect after deploy, re-run the origin query from §1 and watch the "in a job"
rows: `no_user` should stop growing for anything a person triggered, while `sidekiq-cron`
work continues to land unattributed.

## Related

- `app/packs/core/users/models/concerns/trackable.rb` — applies `audited` + `acts_as_paranoid`
- `config/initializers/audited.rb` — sets `Audited.current_user_method`
- `app/packs/core/base/controllers/application_controller.rb` — `show_deleted` /
  `restore_deleted`, including the "Deleted By" column that surfaced this gap
