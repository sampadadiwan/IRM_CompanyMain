# The SideLetterObligationAgent's daily enforcement run (scheduled mode).
#
# Scans the incomplete tasks projected from APPROVED, ACTIVE obligations and
# classifies each as:
#   upcoming — due within the obligation's reminder_days_before (0 suppresses)
#   due      — due today
#   overdue  — past due; re-alerted on the overdue_escalation_days cadence
#
# Sends ONE consolidated notification per recipient per run (owner user; the
# agent's notify_tag employee group for ownerless items and overdue escalations)
# and logs every alert as an ObligationReminder — which is also the idempotency
# guard, so re-running the same day never duplicates alerts.
class ObligationEnforcement < Trailblazer::Operation
  DEFAULT_ESCALATION_DAYS = 3

  step :init
  step :scan
  step :dispatch
  step :persist_report
  left :handle_errors

  def init(ctx, support_agent:, **)
    ctx[:entity] = support_agent.entity
    config = support_agent.json_fields || {}
    ctx[:escalation_days] = config["overdue_escalation_days"].to_i
    ctx[:escalation_days] = DEFAULT_ESCALATION_DAYS unless ctx[:escalation_days].positive?
    # notify_tag employees: fallback recipients for ownerless items + escalation CCs
    ctx[:tag_users] = tag_users(ctx[:entity], config["notify_tag"])
    true
  end

  def scan(ctx, entity:, escalation_days:, **)
    today = Time.zone.today
    items = []

    tasks = Task.incomplete
                .where(entity_id: entity.id, owner_type: "SideLetterObligation")
                .where.not(due_date: nil)
                .includes(owner: { side_letter: { capital_commitment: :investor } })

    tasks.each do |task|
      obligation = task.owner
      next unless obligation&.approved? && obligation.obligation_active?

      kind = classify(task, obligation, today)
      next if kind.nil? || already_alerted?(obligation, task, kind, escalation_days)

      items << { task: task, obligation: obligation, kind: kind }
    end

    ctx[:items] = items
    true
  end

  def dispatch(ctx, support_agent:, entity:, tag_users:, items:, **)
    ctx[:unroutable] = 0

    # recipient User => [items] — one consolidated notification per person
    by_recipient = Hash.new { |h, k| h[k] = [] }
    items.each do |item|
      recipients = recipients_for(item, tag_users)
      ctx[:unroutable] += 1 if recipients.empty?
      recipients.each { |user| by_recipient[user] << item }
    end

    by_recipient.each do |user, user_items|
      ObligationAlertNotifier.with(
        record: support_agent,
        entity_id: entity.id,
        items: user_items.map { |i| serialize(i) }
      ).deliver_later(user)
    end

    # Log AFTER dispatch, once per item (not per recipient) — this is the
    # dedup guard the next run checks. Validation races just skip the row.
    items.each do |item|
      ObligationReminder.create(
        entity_id: entity.id,
        side_letter_obligation: item[:obligation],
        task: item[:task],
        kind: item[:kind].to_s,
        due_date: item[:task].due_date,
        recipient_user_id: item[:obligation].owner_user_id,
        sent_at: Time.current
      )
    end
    true
  end

  # Enforcement leaves its own SupportAgentReport (owner = the entity) so the
  # run shows up on the agent page with its counts.
  def persist_report(ctx, support_agent:, entity:, items:, **)
    counts = items.group_by { |i| i[:kind] }.transform_values(&:count)
    ctx[:counts] = { "upcoming" => 0, "due" => 0, "overdue" => 0 }.merge(counts.transform_keys(&:to_s))

    report = SupportAgentReport.find_or_initialize_by(owner: entity, support_agent: support_agent)
    report.json_fields = (report.json_fields || {}).merge(
      "mode" => "enforcement",
      "run_at" => Time.current.iso8601,
      "completed_at" => Time.current.iso8601,
      "counts" => ctx[:counts],
      "alerted" => ctx[:items].size,
      "unroutable" => ctx[:unroutable],
      "final_status" => "ready"
    )
    report.json_fields_will_change!
    report.status = SupportAgentReport.statuses[:completed]
    report.save!
    report.mark_as_latest!
    ctx[:report] = report
    true
  end

  def handle_errors(ctx, **)
    Rails.logger.error("[ObligationEnforcement] #{ctx[:error]}")
    false
  end

  private

  def classify(task, obligation, today)
    return :due if task.due_date == today
    return :overdue if task.due_date < today
    # reminder_days_before = 0 suppresses pre-due alerts for this obligation
    return :upcoming if obligation.reminder_days_before.positive? &&
                        task.due_date <= today + obligation.reminder_days_before

    nil
  end

  def already_alerted?(obligation, task, kind, escalation_days)
    if kind == :overdue
      ObligationReminder.overdue_sent_within?(obligation, task, escalation_days)
    else
      # upcoming/due fire at most once per obligation per due date
      ObligationReminder.where(side_letter_obligation: obligation, kind: kind.to_s,
                               due_date: task.due_date).exists?
    end
  end

  def recipients_for(item, tag_users)
    recipients = []
    recipients << item[:obligation].owner_user if item[:obligation].owner_user
    # Ownerless items route to the tag group; overdue escalates to it as well
    recipients |= tag_users if recipients.empty? || item[:kind] == :overdue
    recipients
  end

  # Same tag_list resolution as AgentNotificationService#employees_by_tag,
  # but returning User records (the notifier needs recipients, not emails).
  # Safe-by-default (mirrors EsignMonitorAgent's tag-else-primary-email idea):
  # when no tag is configured or it matches nobody, fall back to the entity's
  # company admins so ownerless alerts and escalations always have a recipient.
  def tag_users(entity, tag)
    if tag.present?
      tagged = entity.employees.where("tag_list LIKE ?", "%#{tag}%").to_a
      return tagged if tagged.any?
    end

    User.with_role(:company_admin).where(entity_id: entity.id).to_a
  end

  # String keys on purpose: Noticed params round-trip through JSON, so the
  # mailer view reads item["title"] etc. regardless of delivery timing.
  def serialize(item)
    obligation = item[:obligation]
    {
      "kind" => item[:kind].to_s,
      "obligation_id" => obligation.id,
      "task_id" => item[:task].id,
      "title" => obligation.title,
      "obligation_type" => obligation.obligation_type,
      "investor_name" => obligation.investor.investor_name,
      "source_clause" => obligation.source_clause,
      "due_date" => item[:task].due_date.iso8601
    }
  end
end
