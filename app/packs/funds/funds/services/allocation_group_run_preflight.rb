# Checks every template in an AllocationRunTemplateGroup for a requested period before
# anything runs (decision 3): permission on the fund, a locked period, blocking validation
# rules, a missing statement document, unknown formula tags, and the entity-level "one group
# at a time" guard. A close must never be left half done because of something the system
# could have known up front.
#
#   result = AllocationGroupRunPreflight.call(group:, user:, start_date:, end_date:, resume: true)
#   result[:checks]         # one Check per template in run order
#   result[:group_blockers] # problems with the group as a whole (nothing runs)
#   result[:startable]      # true when nothing is blocked and at least one template will run
#   result[:resume_from]    # the earlier AllocationGroupRun whose successes are being reused
#
# The operation itself never "fails" — a blocked run is a valid, fully described result.
class AllocationGroupRunPreflight < Trailblazer::Operation
  # Severity mirrors ValidationRuleEvaluator: blocker stops the group, warning is shown but allows it.
  Message = Struct.new(:severity, :text, keyword_init: true) do
    def blocker? = severity == "blocker"
    def warning? = severity == "warning"
  end

  # One row of the pre-flight report. status is :ready, :warning, :blocked or :reused.
  Check = Struct.new(:position, :template, :fund, :status, :messages, :reused_run, keyword_init: true) do
    def blocked?  = status == :blocked
    def reused?   = status == :reused
    def warnings  = messages.select(&:warning?)
    def blockers  = messages.select(&:blocker?)
    def will_run? = !reused? && !blocked?
  end

  step :validate_period
  step :find_resume_source
  step :check_group
  step :check_templates
  step :decide

  # Both dates are required and the end must not precede the start.
  def validate_period(ctx, start_date:, end_date:, **)
    ctx[:group_blockers] = []
    ctx[:checks] = []
    if start_date.blank? || end_date.blank?
      ctx[:group_blockers] << "Enter both a start date and an end date."
    elsif end_date < start_date
      ctx[:group_blockers] << "The end date must be on or after the start date."
    end
    true
  end

  # Decision 8(c): when a previous run of this group for the same period exists, resume is the
  # default — templates that succeeded then are reused instead of re-run. resume: false forces
  # a full re-run of every template.
  def find_resume_source(ctx, group:, start_date:, end_date:, resume: true, **)
    ctx[:resume_from] = nil
    return true unless resume && start_date.present? && end_date.present?

    previous = group.allocation_group_runs.finished.for_period(start_date, end_date).recent.first
    # Only a run with at least one success is worth resuming from.
    ctx[:resume_from] = previous if previous&.items&.any? { |i| %w[success reused].include?(i.status) }
    true
  end

  # Group-level problems: an empty group, or another group already running for this entity
  # (decision 10(b): one group run per entity at a time).
  def check_group(ctx, group:, **)
    ctx[:group_blockers] << "This group has no allocation run templates." if group.items.empty?

    if (active = AllocationGroupRun.active_for_entity(group.entity_id))
      ctx[:group_blockers] << "Another allocation run group is already #{active.status} (#{active}). " \
                              "Wait for it to finish before starting this one."
    end
    true
  end

  def check_templates(ctx, group:, user:, start_date:, end_date:, **)
    ctx[:checks] = group.ordered_items.map do |item|
      build_check(ctx, item, user, start_date, end_date)
    end
    true
  end

  # Nothing may be blocked, and at least one template must actually run.
  def decide(ctx, **)
    checks = ctx[:checks]
    if ctx[:group_blockers].empty? && checks.any? && checks.none?(&:will_run?)
      ctx[:group_blockers] << "Every template already succeeded for this period in the previous run. " \
                              "Untick \"Resume from the failed template\" to run them all again."
    end
    ctx[:startable] = ctx[:group_blockers].empty? && checks.any?(&:will_run?) && checks.none?(&:blocked?)
    true
  end

  private

  def build_check(ctx, item, user, start_date, end_date)
    template = item.allocation_run_template
    fund = template.fund
    check = Check.new(position: item.position, template:, fund:, status: :ready, messages: [], reused_run: nil)

    # A template that succeeded in the run being resumed is reused, not re-run.
    if (reused = reusable_run(ctx[:resume_from], template))
      check.status = :reused
      check.reused_run = reused
      check.messages << Message.new(severity: "info",
                                    # This exact string is later copied onto AllocationGroupRunItem#message and
                                    # rendered as plain text inside AllocationGroupRunMailer, which has no view
                                    # context to apply EmailDateLocalization's l() override. This is a .rb file,
                                    # not a mailer view, so the email date rule has to be applied explicitly here.
                                    text: "Succeeded in the previous run for this period (#{I18n.l(reused.created_at, format: :email, locale: :en)}); it will not be run again.")
      return check
    end

    # Dates are missing or inverted — nothing more can be checked sensibly.
    return check if start_date.blank? || end_date.blank? || end_date < start_date

    check_permission(check, user, fund)
    check_template_integrity(check, template, fund)
    check_locked_period(check, template, fund, start_date, end_date)
    check_validation_rules(check, template, fund, start_date, end_date)
    check_period_gap(check, fund, start_date)

    check.status = if check.blockers.any? then :blocked
                   elsif check.warnings.any? then :warning
                   else :ready
                   end
    check
  end

  # A success (or reuse of a success) for the same template in the run being resumed.
  def reusable_run(resume_from, template)
    return nil unless resume_from

    prior = resume_from.items.detect { |i| i.allocation_run_template_id == template.id && %w[success reused].include?(i.status) }
    prior&.allocation_run
  end

  # Decision 4: permission is checked on each template's fund, not just on the group.
  def check_permission(check, user, fund)
    return if FundPolicy.new(user, fund).allocate?

    check.messages << Message.new(severity: "blocker", text: "You do not have the right to run allocations on #{fund.name}.")
  end

  # Decisions 15 and 16: a vanished statement document or an unknown formula tag is a wrong
  # close, not a cosmetic issue, so both block. A sample run is almost never intended for a close.
  def check_template_integrity(check, template, _fund)
    if template.generate_soa? && template.statement_document.blank?
      check.messages << Message.new(severity: "blocker",
                                    text: "The statement document this template generates statements with no longer exists on the fund. Edit the template and pick another.")
    end

    unknown = template.unknown_tags
    if unknown.any?
      check.messages << Message.new(severity: "blocker",
                                    text: "Formula #{'tag'.pluralize(unknown.size)} #{unknown.map { |t| "\"#{t}\"" }.join(', ')} no longer #{unknown.size == 1 ? 'exists' : 'exist'} in the entity settings, so fewer formulas would run than intended.")
    end

    return unless template.sample?

    check.messages << Message.new(severity: "warning", text: "This template runs as a sample (a few folios only). A close is normally run on every folio.")
  end

  # Same rule as a manual run: a locked run overlapping the period refuses a formula run.
  def check_locked_period(check, template, fund, start_date, end_date)
    return unless template.run_allocations?

    locked = AllocationRun.locked_and_overlapping(fund.id, start_date, end_date)
    return unless locked

    check.messages << Message.new(severity: "blocker",
                                  text: "A locked allocation run already covers #{I18n.l(locked.start_date)} – #{I18n.l(locked.end_date)} on #{fund.name}. Unlock it first if this period really needs re-running.")
  end

  # The same validation rules a manual run evaluates, on a temporary unsaved AllocationRun.
  def check_validation_rules(check, template, fund, start_date, end_date)
    temp_run = AllocationRun.new(entity_id: fund.entity_id, fund_id: fund.id, start_date:, end_date:, locked: false,
                                 run_allocations: template.run_allocations, generate_soa: template.generate_soa)
    ValidationRuleEvaluator.call(record: temp_run, entity: fund.entity).each do |result|
      # Warnings and blockers only; the rule engine has no other severities today.
      severity = result.blocker? ? "blocker" : "warning"
      text = result.message.to_s
      next if check.messages.any? { |m| m.text == text }

      check.messages << Message.new(severity:, text:)
    end
  rescue StandardError => e
    # A broken rule must not stop a close on its own — surface it as a warning instead.
    Rails.logger.error("[AllocationGroupRunPreflight] rule evaluation failed for fund #{fund.id}: #{e.message}")
    check.messages << Message.new(severity: "warning", text: "Validation rules could not be evaluated (#{e.message}).")
  end

  # Decision 12(b): warn, but allow, when the period does not start the day after the
  # previous locked run ended — usually a typo in the dates, but a first period or a
  # corrected re-run must still be possible.
  def check_period_gap(check, fund, start_date)
    previous = AllocationRun.where(fund_id: fund.id).locked.where(end_date: ...start_date).order(end_date: :desc).first
    return unless previous
    return if previous.end_date + 1.day == start_date

    check.messages << Message.new(severity: "warning",
                                  text: "The last locked run on #{fund.name} ended on #{I18n.l(previous.end_date)}; this period starts on #{I18n.l(start_date)}, leaving a gap.")
  end
end
