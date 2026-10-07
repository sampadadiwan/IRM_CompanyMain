# Works out where an evaluated workflow (one with system/acknowledge steps) actually is, from the
# record's data, and records what changed. It is the only place that moves an evaluated instance's
# pointer forwards or backwards.
#
# One evaluation:
#   1. lock the instance (one evaluation at a time)
#   2. walk the snapshot steps top to bottom: does it apply? is it done? stop at the first not done
#   3. compare with the last evaluation: moved forward, moved back, or the same
#   4. cause :undo only — reset sign-offs on later steps given before the undo started
#   5. save only if something changed; send emails after commit
#
# Human-only instances (evaluated = false) are never touched: the guard returns straight away, so
# today's approval workflows keep their exact behaviour.
#
# IMPORTANT: callers must NOT wrap this in their own transaction (same rule as WorkflowAdvancer):
# emails are sent after this operation's own transaction commits.
class WorkflowEvaluator < Trailblazer::Operation
  # Why an approval step with no approvers picked yet is n/a (see skip_result)
  NO_APPROVER = "No approver set — pick one on this step in the journey template".freeze

  # Passive evaluations of a completed journey stop this long after completion (the tick's horizon)
  COMPLETE_HORIZON = 30.days

  step :guard
  step :evaluate
  step :notify

  # Evaluate the current journey of any workflowable record; nil when it has none
  def self.for(record, cause: :progress, actor: nil, note: nil, undo_started_at: nil)
    instance = record.workflow_instances.where(evaluated: true).where.not(status: :archived).order(created_at: :desc).first
    return nil unless instance

    call(instance:, cause:, actor:, note:, undo_started_at:)
  end

  def guard(ctx, instance:, cause: :progress, **)
    ctx[:results] = results_from_cache(instance)
    return false unless instance.evaluated && !instance.instance_archived?
    return false if instance.instance_rejected?
    # A long-finished journey is only re-checked when someone undoes something
    return false if cause.to_sym != :undo && instance.instance_complete? &&
                    instance.completed_at.present? && instance.completed_at < COMPLETE_HORIZON.ago

    true
  end

  def evaluate(ctx, instance:, cause: :progress, actor: nil, note: nil, undo_started_at: nil, persist: true, **)
    ctx[:mails] = []
    if persist
      ActiveRecord::Base.transaction do
        instance.lock!
        instance.reload
        ctx[:results] = run(ctx, instance, cause.to_sym, actor, note, undo_started_at, persist: true)
      end
    else
      ctx[:results] = run(ctx, instance, cause.to_sym, actor, note, undo_started_at, persist: false)
    end
    true
  end

  # Emails are sent only after the transaction has committed
  def notify(ctx, instance:, actor: nil, **)
    # Open pages showing this record's journey update themselves (e.g. the capital call page's
    # step bar ticks over when notice generation finishes) — only when something actually changed
    broadcast_change(instance) if ctx[:changed]

    ctx[:mails].each do |mail|
      case mail[:type]
      when :activation
        # The person whose action moved the journey on is already on the page — don't email them
        WorkflowStepActorNotifier.call(instance:, step_position: mail[:position], except_user_id: actor&.id)
      when :review_needed, :journey_complete
        owner_mail(instance, mail, actor)
      when :sign_off_reset
        # Someone who undid work themselves isn't told their own sign-off was reset
        next if actor && mail[:user_id].to_i == actor.id

        user = User.find_by(id: mail[:user_id])
        next unless user

        WorkflowNotifier.with(record: instance, entity_id: instance.entity_id, email_method: :sign_off_reset,
                              step_position: mail[:position], reason: mail[:reason]).deliver_later(user)
      end
    end
    true
  end

  private

  # Emails the step's owner — the same person the stalled-step reminder goes to. Nobody resolves
  # (no owner set and no creator on record, or an inactive owner) → no email; the diagram and the
  # journey panel already show "Owner unavailable" for that case. Nor when the owner is the person
  # whose action just moved the journey on (e.g. Mark reviewed on one review step making the next
  # one current) — they are already looking at it.
  def owner_mail(instance, mail, actor)
    step = instance.snapshot_steps.find { |s| s[:position].to_i == mail[:position] }
    return unless step

    # Every resolved owner (one for most journeys; a KPI report may have several) — minus the actor
    WorkflowAutoReminderJob.owners_for(instance, step).each do |owner|
      next if actor && owner.id == actor.id

      WorkflowNotifier.with(record: instance, entity_id: instance.entity_id, email_method: mail[:type],
                            step_position: mail[:position]).deliver_later(owner)
    end
  end

  # Worked examples H2, H8 (walk), E3, E4, E22, E23 (n/a), X6 (errors) — openspec/changes/archive/2026-10-02-capital-call-journey/design.md#worked-examples
  # ── The walk ────────────────────────────────────────────────────────────────

  def run(ctx, instance, cause, actor, note, undo_started_at, persist:)
    record = instance.workflowable
    steps = instance.snapshot_steps
    old_results = (instance.step_results || {}).transform_keys(&:to_s)
    old_position = instance.current_step_position
    history = History.new(instance)
    now = Time.current

    results = []
    # Who passed each step (the confirmation / vote behind it), so the history row names them
    evidence = {}
    current = nil
    previous_passed_at = instance.created_at
    # A passing closing check (KYC "Verify KYC") closes every unfinished step before it
    closing = closing_step(steps, record)

    steps.each do |step|
      pos = step[:position].to_i
      old = old_results[pos.to_s] || {}

      # Below the current step, only work out whether a step is n/a (for the step bar)
      if current
        # Below the current step only the n/a reason is worked out; an error here just shows "not yet"
        skip = begin
          skip_result(step, record)
        rescue StandardError
          nil
        end
        results << if skip&.passed?
                     base_result(step).merge(status: "na", message: skip.message)
                   else
                     base_result(step).merge(status: "not_yet")
                   end
        next
      end

      outcome = judge(step, record, instance, history)
      # Worked examples E6 — openspec/changes/investor-kyc-journey/design.md#worked-examples
      outcome = { status: "na", message: closing[:note] } if closing && pos < closing[:position] && outcome[:status] == "current"

      case outcome[:status]
      when "na"
        results << base_result(step).merge(status: "na", message: outcome[:message])
      when "passed"
        # Worked examples H15 — openspec/changes/archive/2026-10-02-capital-call-journey/design.md#worked-examples
        # Pass time is stamped once (design Decision 17): keep it if this step was already passed
        passed_at = if old["status"] == "passed" && old["passed_at"].present?
                      Time.zone.parse(old["passed_at"])
                    else
                      clamp(outcome[:passed_since] || now, previous_passed_at, now)
                    end
        previous_passed_at = passed_at
        evidence[pos] = outcome[:response]
        results << base_result(step).merge(status: "passed", message: outcome[:message], passed_at: passed_at.iso8601)
      else # "current" or "error"
        current = step
        row = base_result(step).merge(status: outcome[:status], message: outcome[:message],
                                      action_label: outcome[:action_label], action_path: outcome[:action_path],
                                      action_target: outcome[:action_target])
        # An acknowledge check's own button beside "Mark reviewed" — only when it asked for one, so
        # other journeys' stored results stay byte-identical (no new nil keys)
        row.merge!(outcome.slice(:review_action_label, :review_action_path, :review_action_target, :review_action_new_tab).compact)
        # The main button opens in a new tab — likewise only when the check asked (KPI approvals, H19)
        row[:action_new_tab] = true if outcome[:action_new_tab]
        results << row
      end
    end

    new_position = current ? current[:position].to_i : old_position
    complete = current.nil?
    moved_back = !complete && (new_position < old_position || reopened?(instance, complete))

    # Time the current step started: unchanged if we're still on the same step and didn't move back
    since = if complete
              nil
            elsif new_position == old_position && !moved_back && instance.current_step_since.present?
              instance.current_step_since
            elsif moved_back
              now
            else
              clamp(previous_passed_at, instance.created_at, now)
            end

    if current
      cur = results.find { |r| r[:position] == new_position }
      cur[:since] = since&.iso8601
      cur.merge!(history.regression_info(new_position)) unless moved_back
    end

    return results.map(&:stringify_keys) unless persist

    # ── Record what changed ───────────────────────────────────────────────────
    # Worked examples E29 — openspec/changes/archive/2026-10-02-capital-call-journey/design.md#worked-examples
    results.each do |r|
      old = old_results[r[:position].to_s] || {}
      next if old["status"] == r[:status]

      # from_state is the step's previous evaluated status, so a row like passed → n/a reads as a change
      from_state = old["status"]
      if r[:status] == "passed"
        # A step passed by a person (confirmation or vote) is recorded against them and their channel;
        # one passed by a system check stays a system event with no actor
        response = evidence[r[:position]]
        history.write(r[:position], "passed", note: r[:message], from_state:, actor: response&.actor,
                                              channel: response&.channel || :system)
      end
      history.write(r[:position], "skipped", note: r[:message], from_state:) if r[:status] == "na" && from_state.present?
    end

    # Worked examples E7, E11, E18 (moved back / reopened) — openspec/changes/archive/2026-10-02-capital-call-journey/design.md#worked-examples
    if moved_back
      reason = note.presence || "Data changed"
      history.write(new_position, "regressed", note: reason, actor: actor,
                                               from_state: old_results.dig(new_position.to_s, "status"))
      if (cur = results.find { |r| r[:position] == new_position })
        cur.merge!(regressed: true, regressed_reason: reason, regressed_by: actor&.id)
      end
    end
    history.write(new_position, "reopened", note: note, actor: actor, from_state: "complete") if reopened?(instance, complete)

    # Worked examples E8, E9, E10, E10c — openspec/changes/archive/2026-10-02-capital-call-journey/design.md#worked-examples
    # Only a user's undoing action resets sign-offs (design Decision 11)
    reset_later_sign_offs(ctx, instance, steps, new_position, undo_started_at || now, history, note, actor, old_results) if cause == :undo && !complete

    # Worked examples H16 — openspec/changes/archive/2026-10-02-capital-call-journey/design.md#worked-examples
    # A human step that just became current: tell its approvers
    ctx[:mails] << { type: :activation, position: new_position } if current && current[:kind].to_s == "human" && (new_position != old_position || moved_back)

    # An acknowledge step that just became current: tell its owner now rather than leaving it to the
    # stalled-step reminder days later. Never on a record's first evaluation (launch / rollout onto
    # existing records), and not when the step is set to stay silent on activation.
    first_evaluation = old_results.empty?
    became_current = current && (new_position != old_position || moved_back)
    review_now = became_current && !first_evaluation && current[:kind].to_s == "acknowledge" && current[:notify_on_activation]
    ctx[:mails] << { type: :review_needed, position: new_position } if review_now

    # The journey just finished: tell the owner of the last step (or the record's creator). Not on a
    # first evaluation, so launching journeys on already-finished records emails nobody.
    ctx[:mails] << { type: :journey_complete, position: steps.last[:position].to_i } if complete && !instance.instance_complete? && !first_evaluation

    attrs = {
      current_step_position: new_position,
      current_step_since: since,
      step_results: results.to_h { |r| [r[:position].to_s, r.except(:position).stringify_keys] },
      status: complete ? :complete : :active
    }
    attrs[:completed_at] = results.filter_map { |r| r[:passed_at] }.max.then { |t| t ? Time.zone.parse(t) : now } if complete && !instance.instance_complete?
    if changed?(instance, attrs)
      instance.update!(attrs)
      ctx[:changed] = true
    end
    ctx[:changed] ||= history.written?

    results.map(&:stringify_keys)
  end

  # Decide one step: n/a, passed, current or error
  def judge(step, record, instance, history)
    skip = skip_result(step, record)
    if skip&.passed?
      # Worked examples E29 — openspec/changes/archive/2026-10-02-capital-call-journey/design.md#worked-examples
      # A review someone actually confirmed stays done even once the skip applies (e.g. notices
      # sent afterwards): the skip exists so a missing review never blocks, not to erase a real one
      response = acknowledgement(step, instance, history) if step[:kind].to_s == "acknowledge"
      return reviewed(response) if response

      return { status: "na", message: skip.message }
    end

    case step[:kind].to_s
    when "system" then judge_system(step, record, history)
    when "acknowledge" then judge_acknowledge(step, record, instance, history)
    else judge_human(step, instance, history)
    end
  rescue StandardError => e
    report(e, instance, step)
    { status: "error", message: "Could not check this step — support has been notified" }
  end

  def judge_system(step, record, history)
    result = WorkflowChecks::Registry.fetch(step[:check_key]).call(record)
    return current_from(result) unless result.passed?

    # After an invalidation, the evidence (or a refresh marker such as "recomputed") must be newer
    invalidated_at = history.last_at(step[:position], "invalidated")
    if invalidated_at
      fresh = [result.fresh_since, history.last_at(step[:position], "recomputed")].compact.max
      unless fresh && fresh > invalidated_at
        return { status: "current", message: history.last_note(step[:position], "invalidated") || "Needs to be done again",
                 action_label: result.action_label, action_path: result.action_path, action_target: result.action_target,
                 action_new_tab: (true if result.new_tab) }
      end
    end

    { status: "passed", message: result.message, passed_since: result.passed_since }
  end

  # Worked examples H4, E12 — openspec/changes/archive/2026-10-02-capital-call-journey/design.md#worked-examples
  def judge_acknowledge(step, record, instance, history)
    result = nil
    if step[:check_key].present?
      result = WorkflowChecks::Registry.fetch(step[:check_key]).call(record)
      return current_from(result) unless result.passed?
    end

    invalidated_at = history.last_at(step[:position], "invalidated")
    # Worked examples H5, E5 — openspec/changes/investor-kyc-journey/design.md#worked-examples
    # The data confirms it (an AI pass): done with no click, unless that evidence predates an invalidation
    confirmed = result&.review == :confirmed && (invalidated_at.nil? || (result.fresh_since && result.fresh_since > invalidated_at))
    return { status: "passed", message: result.message, passed_since: result.passed_since } if confirmed

    response = acknowledgement(step, instance, history)
    return reviewed(response) if response

    # Worked examples E3, E4 — openspec/changes/investor-kyc-journey/design.md#worked-examples
    # A check that asked for review supplies the message and a second button; the invalidation reason still wins
    if result&.review == :requested
      return { status: "current", message: invalidated_at ? history.last_note(step[:position], "invalidated") : result.message,
               action_label: "Mark reviewed", review_action_label: result.action_label,
               review_action_path: result.action_path, review_action_target: result.action_target,
               review_action_new_tab: (true if result.new_tab) }
    end

    message = invalidated_at ? history.last_note(step[:position], "invalidated") : "Not confirmed yet"
    { status: "current", message: message, action_label: "Mark reviewed" }
  end

  # The last step whose check is a closing check and passes ({position:, note:}), or nil. A failing
  # or raising closing check closes nothing (the walk is then the normal one).
  # Worked examples E6, E11 — openspec/changes/investor-kyc-journey/design.md#worked-examples
  def closing_step(steps, record)
    steps.reverse_each do |step|
      next unless step[:kind].to_s == "system" && step[:check_key].present?

      check = WorkflowChecks::Registry.fetch(step[:check_key])
      next unless check.class.closes_journey

      return { position: step[:position].to_i, note: check.class.closing_note } if check.call(record).passed?
    rescue StandardError
      next
    end
    nil
  end

  # The latest "Mark reviewed" on an acknowledge step that still counts: active, and given after the
  # step was last invalidated (an email edit, an undo). nil when there is none.
  def acknowledgement(step, instance, history)
    response = instance.workflow_actor_responses.active.for_step(step[:position]).order(:responded_at).last
    return nil unless response

    invalidated_at = history.last_at(step[:position], "invalidated")
    response if invalidated_at.nil? || response.responded_at > invalidated_at
  end

  # A passed outcome for an acknowledge step, carrying the confirmation so history can name its actor
  def reviewed(response)
    { status: "passed", message: "Reviewed by #{response.actor&.full_name}", passed_since: response.responded_at, response: }
  end

  # Worked examples H8, E26 — openspec/changes/archive/2026-10-02-capital-call-journey/design.md#worked-examples
  def judge_human(step, instance, history)
    resolution = WorkflowStepResolver.call(instance:, step_position: step[:position].to_i)[:resolution]
    first_state = step[:states].to_s.split(",").first&.strip
    if resolution[:resolved].present? && resolution[:resolved] == first_state
      # The last vote is the one that resolved the step: its time is the pass time, its actor the history's
      last_vote = instance.workflow_actor_responses.active.for_step(step[:position]).order(:responded_at).last
      return { status: "passed", message: first_state.to_s, passed_since: last_vote&.responded_at, response: last_vote }
    end

    rejected = history.last_event(step[:position], "rejected_step")
    message = rejected ? rejected.note : "Waiting for #{step[:name]}"
    { status: "current", message: message }
  end

  def current_from(result)
    { status: "current", message: result.message, action_label: result.action_label, action_path: result.action_path,
      action_target: result.action_target, action_new_tab: (true if result.new_tab) }
  end

  # The skip check's result for a step (nil when it has none); a passing result means "n/a" and its
  # message is the reason shown on hover
  def skip_result(step, record)
    # A sign-off step nobody has been picked for yet (e.g. the seeded CFO sign-off) is n/a rather
    # than waiting forever: approvers are frozen into the instance at launch, so picking them on the
    # template later only reaches journeys launched afterwards.
    # Worked examples E24 — openspec/changes/archive/2026-10-02-capital-distribution-journey/design.md#worked-examples
    return WorkflowChecks::Result.pass(message: NO_APPROVER) if step[:kind].to_s == "human" && Array(step[:actor_ids]).empty?
    return nil if step[:skip_key].blank?

    WorkflowChecks::Registry.fetch(step[:skip_key]).call(record)
  end

  # ── Sign-off reset ──────────────────────────────────────────────────────────

  def reset_later_sign_offs(ctx, instance, steps, current_position, undo_started_at, history, note, actor, old_results)
    steps.each do |step|
      pos = step[:position].to_i
      next if pos <= current_position
      next if step[:kind].to_s == "system" || step[:keep_on_regress]

      responses = instance.workflow_actor_responses.active.for_step(pos).where(responded_at: ...undo_started_at)
      next unless responses.exists?

      actor_ids = responses.distinct.pluck(:actor_id)
      responses.update_all(archived: true, updated_at: Time.current)
      history.write(pos, "invalidated", note: "Sign-off reset: #{note.presence || 'earlier work was undone'}", actor: actor,
                                        from_state: old_results.dig(pos.to_s, "status"))

      # Approvers of human steps are told; acknowledge confirmations show in history only
      next unless step[:kind].to_s == "human"

      actor_ids.each do |user_id|
        ctx[:mails] << { type: :sign_off_reset, user_id:, position: pos, reason: note.presence || "Earlier work was undone" }
      end
    end
  end

  # ── Helpers ─────────────────────────────────────────────────────────────────

  def base_result(step)
    { position: step[:position].to_i, name: step[:name], kind: step[:kind].presence || "human" }
  end

  def clamp(time, lower, upper)
    [[time, lower].compact.max, upper].min
  end

  def reopened?(instance, complete)
    instance.instance_complete? && !complete
  end

  def changed?(instance, attrs)
    attrs.any? do |key, value|
      current = instance.public_send(key)
      key == :status ? current.to_s != value.to_s : current != value
    end
  end

  def results_from_cache(instance)
    (instance.step_results || {}).map { |pos, r| r.merge("position" => pos.to_i) }.sort_by { |r| r["position"] }
  end

  # Never lets a broadcast problem fail an evaluation (the page still updates on its next view)
  def broadcast_change(instance)
    instance.workflowable.broadcast_journey_change
  rescue StandardError => e
    Rails.logger.error("[WorkflowEvaluator] journey broadcast for instance #{instance.id}: #{e.class}: #{e.message}")
  end

  def report(error, instance, step)
    Rails.logger.error("[WorkflowEvaluator] entity=#{instance.entity_id} instance=#{instance.id} " \
                       "#{instance.workflowable_type}##{instance.workflowable_id} step=#{step[:position]} " \
                       "check=#{step[:check_key]}: #{error.class}: #{error.message}")
    ExceptionNotifier.notify_exception(error, data: { instance_id: instance.id, step: step[:position], check: step[:check_key] })
  end

  # Reads the instance's history once per evaluation
  class History
    EVENTS = %w[invalidated recomputed regressed passed rejected_step].freeze

    def initialize(instance)
      @instance = instance
      @events = instance.workflow_state_changes.where(to_state: EVENTS).order(:created_at).to_a
    end

    def last_event(position, to_state)
      @events.rfind { |e| e.step_position == position.to_i && e.to_state == to_state }
    end

    def last_at(position, to_state)
      last_event(position, to_state)&.created_at
    end

    def last_note(position, to_state)
      last_event(position, to_state)&.note
    end

    # For the current step: was it reached by moving back, and why (shown as ↺ and in the banner)
    def regression_info(position)
      regressed = last_event(position, "regressed")
      passed = last_event(position, "passed")
      return { regressed: false } unless regressed && (passed.nil? || regressed.created_at > passed.created_at)

      { regressed: true, regressed_reason: regressed.note, regressed_by: regressed.actor_id }
    end

    # channel defaults to :system; a step passed by a person's confirmation or vote passes theirs
    def written?
      @written == true
    end

    def write(position, to_state, note: nil, actor: nil, from_state: nil, channel: :system)
      @written = true
      event = WorkflowStateChange.create!(workflow_instance: @instance, step_position: position.to_i, to_state:,
                                          from_state:, note:, actor:, channel:)
      @events << event
      event
    end
  end
end
