# ⑩ Getting started (Phase 5): the 8 setup steps on Compliance home, worked out from the firm's own data
# on every view. Nothing is stored as "done" (D14, R150), so a step reopens by itself when setup changes
# (E180) and the panel can never disagree with the setup. Read-only: only exists?/count queries on small
# compliance tables; no large table is touched.
#
#   1 owner     owner set and ≥ 1 eligible approver (a single approver counts, with a note — E183)
#   2 attach    ≥ 1 active fund pack
#   3 inputs    every required input the attached checks read is mapped (ComplianceInputs)
#   4 lists     every reference list an attached content check reads has entries; none needed → not needed (E181)
#   5 first_run ≥ 1 succeeded run (Run now offered on the first attached fund — U11)
#   6 recipients ≥ 1 active user tagged Compliance (the digest goes to them)
#   7 monitoring monitoring switched on (E191: still refused while an input is missing — the X15 gate)
#   8 owned     every open register item has an assignee, or is pending approval or explained
#
# Worked examples H80–H83, E180–E183, E191 — openspec/changes/archive/2026-11-06-fund-compliance-monitoring/business-rules.md
class ComplianceGettingStarted
  STEPS = %w[owner attach inputs lists first_run recipients monitoring owned].freeze

  Step = Struct.new(:key, :state, :label, :detail, :why, :action_label, :action_path, :action_method, :can_act, :note, keyword_init: true) do
    def done?
      %w[done not_needed].include?(state)
    end
  end

  Result = Struct.new(:steps, :done_count, :current, keyword_init: true) do
    def complete?
      current.nil?
    end
  end

  def self.call(entity:, user:)
    new(entity, user).call
  end

  def initialize(entity, user)
    @entity = entity
    @user = user
    @setup = ComplianceEntitySetup.for(entity)
    @fund_packs = FundCompliancePack.active.where(entity_id: entity.id).includes(:fund, :compliance_pack, :compliance_pack_version).to_a
    @editor = ComplianceAccess.editor?(user)
  end

  def call
    steps = STEPS.map { |key| send(:"#{key}_step") }
    # The first step not done is current; later ones stay to-do (they may already be true, then shown done)
    current = steps.find { |s| !s.done? }
    current.state = "current" if current
    Result.new(steps:, done_count: steps.count(&:done?), current:)
  end

  # E201: the specifics behind one step, shown in its popup (the rail's circles open it, as on every other
  # journey). Worked out from the same data as the panel; read-only. Each line is { label:, text:, ok: }
  # where ok is true (✓), false (✗) or nil (neutral). Unknown keys return nil (X95 → 404 in the controller).
  def details(key)
    return nil unless STEPS.include?(key.to_s)

    send(:"#{key}_details")
  end

  # Reference lists the attached content checks read that their packs do not ship themselves (E181) —
  # also what the Setup page's list editor shows
  def needed_lists
    @fund_packs.flat_map do |fp|
      v = fp.compliance_pack_version
      next [] unless v

      shipped = Array(v.definition_hash["reference_lists"]).select { |l| Array(l["entries"]).any? }.pluck("key")
      v.checks.select { |c| c["kind"] == "content" && ComplianceContentCheck::LIST_RULES.include?(c["rule"]) && c["list"].present? }
       .select { |c| c["applies_to"].nil? || c["applies_to"] == "all" || Array(c["applies_to"]).include?(fp.classification) }
       .pluck("list") - shipped
    end.uniq
  end

  private

  def routes
    Rails.application.routes.url_helpers
  end

  def tr(key, **)
    I18n.t("compliance.getting_started.steps.#{key}", **)
  end

  def step(key, done, detail: nil, path: nil, method: :get, can_act: @editor, note: nil, state: nil, **)
    Step.new(key:, state: state || (done ? "done" : "todo"), label: tr("#{key}.label"), detail: detail || tr("#{key}.todo", **),
             why: tr("#{key}.why", **), action_label: tr("#{key}.action", **), action_path: path, action_method: method,
             can_act:, note:)
  end

  # 1. E183: one eligible person is enough — their approvals are labelled Self-approved (R11)
  def owner_step
    approvers = ComplianceAccess.eligible_approvers(@entity)
    done = @setup.persisted? && @setup.owner_id.present? && approvers.any?
    note = tr("owner.single") if done && approvers.size == 1
    step("owner", done, path: routes.compliance_entity_setup_path, note:)
  end

  def attach_step
    # R175: the Home funds grid, where every row has Attach
    step("attach", @fund_packs.any?, path: routes.compliance_home_path(tab: ComplianceHub.pane_id(:home), anchor: "compliance_funds"))
  end

  # 3. H81 / E180: names the unmapped inputs and how many checks they block
  def inputs_step
    missing = @fund_packs.any? ? ComplianceInputs.for(@entity).select(&:missing?) : []
    done = @fund_packs.any? && missing.empty?
    names = missing.map(&:label).join(", ")
    packs = missing.flat_map(&:packs).uniq.join(", ")
    checks = ComplianceInputs.blocked_checks_count(@entity, missing.map(&:key))
    detail = missing.any? ? tr("inputs.todo", count: ActionController::Base.helpers.pluralize(missing.size, "input"), packs:, names:) : nil
    step("inputs", done, detail:, path: routes.compliance_entity_setup_path(anchor: "setup_inputs"),
                         checks: ActionController::Base.helpers.pluralize(checks, "check"),
                         count: missing.size, packs:, names:)
  end

  # 4. E181: lists only count when an attached content check reads one the pack does not ship itself
  def lists_step
    needed = needed_lists
    return step("lists", true, state: "not_needed", detail: tr("lists.not_needed"), names: "") if @fund_packs.any? && needed.empty?

    missing = needed.reject { |key| @setup.reference_list(key).any? }
    names = missing.map(&:humanize).join(", ")
    step("lists", @fund_packs.any? && missing.empty?, path: routes.compliance_entity_setup_path(anchor: "setup_lists"), names:)
  end

  # 5. U11: Run now on the first attached fund, so results arrive today
  def first_run_step
    done = ComplianceRun.exists?(entity_id: @entity.id, status: "succeeded")
    fp = @fund_packs.min_by { |f| [f.fund.name, f.id] }
    fund = fp&.fund&.name || "a fund"
    can = fp ? Pundit.policy(@user, fp).run_now? : false
    step("first_run", done, path: fp && routes.run_now_fund_compliance_pack_path(fp), method: :post, can_act: can, fund:)
  end

  def recipients_step
    step("recipients", tagged_users.any?, path: routes.users_path, can_act: @user.has_cached_role?(:company_admin))
  end

  def monitoring_step
    step("monitoring", @setup.monitoring_enabled?, path: routes.compliance_entity_setup_path(anchor: "setup_monitoring"))
  end

  # 8. Every breach episode needs someone on it before its fix-by date
  def owned_step
    unowned = ComplianceRegisterItem.open_items.where(entity_id: @entity.id, assignee_id: nil)
                                    .where.not(status: %w[pending_approval explained]).count
    # Not "done" before any run: with no results there is nothing yet to own
    ran = ComplianceRun.exists?(entity_id: @entity.id, status: "succeeded")
    step("owned", ran && unowned.zero?, path: routes.compliance_register_items_path,
                                        count: ActionController::Base.helpers.pluralize(unowned, "open item"))
  end

  # ── Popup specifics (E201) ─────────────────────────────────────────────────────────────────────

  def line(text, ok = nil, label: nil)
    { label:, text:, ok: }
  end

  def none
    I18n.t("compliance.getting_started.details.none")
  end

  # The owner and every eligible approver (company admins included, as maker–checker counts them)
  def owner_details
    approvers = ComplianceAccess.eligible_approvers(@entity)
    [line(@setup.owner&.full_name || none, @setup.owner.present?, label: tr("owner.details.owner")),
     line(approvers.map(&:full_name).join(", ").presence || none, approvers.any?, label: tr("owner.details.approvers"))]
  end

  # Every attached fund × pack, plus how many visible funds still carry none (never shown as compliant, E10)
  def attach_details
    lines = @fund_packs.sort_by { |fp| [fp.fund.name, fp.pack_name] }.map do |fp|
      parts = [fp.pack_name, fp.classification.presence, fp.compliance_pack_version&.label].compact
      line(parts.join(" · "), true, label: fp.fund.name)
    end
    lines = [line(none, false)] if lines.empty?
    unmonitored = ComplianceAccess.fund_ids(@user).size - @fund_packs.map(&:fund_id).uniq.size
    lines << line(tr("attach.details.unmonitored", count: unmonitored)) if unmonitored.positive?
    lines
  end

  # Each input the attached checks read: mapped, optional, or the checks a missing one blocks (H81)
  def inputs_details
    inputs = ComplianceInputs.for(@entity)
    return [line(tr("inputs.details.no_packs"), nil)] if inputs.empty?

    inputs.map do |inp|
      label = "#{inp.label.upcase_first} (#{inp.packs.join(', ')})"
      if inp.missing?
        blocked = ComplianceInputs.blocked_checks_count(@entity, [inp.key])
        missing = inp.type == "fund_figure" ? tr("inputs.details.missing_for", funds: inp.missing_funds.join(", ")) : tr("inputs.details.unmapped")
        line("#{missing} — #{tr('inputs.details.blocks', count: ActionController::Base.helpers.pluralize(blocked, 'check'))}", false, label:)
      elsif inp.optional && !inp.mapped
        line(tr("inputs.details.optional"), nil, label:)
      else
        line(tr("inputs.details.mapped"), true, label:)
      end
    end
  end

  # Each list an attached content check reads, with its entry count — or "not needed" (E181)
  def lists_details
    needed = needed_lists
    return [line(tr("lists.not_needed"), nil)] if needed.empty?

    needed.map do |key|
      n = @setup.reference_list(key).size
      line(ActionController::Base.helpers.pluralize(n, "entry"), n.positive?, label: key.humanize)
    end
  end

  # The firm's last successful run, in its own time zone
  def first_run_details
    last = ComplianceRun.where(entity_id: @entity.id, status: "succeeded").includes(:fund).order(:created_at, :id).last
    return [line(tr("first_run.details.none"), false)] unless last

    at = I18n.l(last.created_at.in_time_zone(@setup.time_zone.presence || "Asia/Kolkata"), format: :abbr_date_time)
    [line("#{last.fund&.name} · #{at} (#{last.trigger == 'nightly' ? 'nightly' : 'Run now'})", true, label: tr("first_run.details.last"))]
  end

  def recipients_details
    users = tagged_users
    return [line(tr("recipients.details.none"), false)] if users.empty?

    users.map { |u| line(u.full_name, true) }
  end

  # On since when; off → why it may be refused (X15: monitoring stays off while an input is missing)
  def monitoring_details
    if @setup.monitoring_enabled?
      since = @setup.monitoring_since
      return [line(since ? tr("monitoring.details.switched_on", since: I18n.l(since)) : tr("monitoring.details.switched_on_undated"), true)]
    end

    lines = [line(tr("monitoring.details.switched_off"), false)]
    missing = ComplianceInputs.missing_labels(@entity)
    lines << line(tr("monitoring.details.refused", names: missing.join(", "))) if missing.any?
    lines
  end

  # Open items nobody owns (up to 10, then "and N more")
  def owned_details
    return [line(tr("owned.details.no_results"), nil)] unless ComplianceRun.exists?(entity_id: @entity.id, status: "succeeded")

    scope = ComplianceRegisterItem.open_items.where(entity_id: @entity.id, assignee_id: nil)
                                  .where.not(status: %w[pending_approval explained])
    total = scope.count
    return [line(tr("owned.details.all_owned"), true)] if total.zero?

    lines = scope.includes(:fund).order(:fix_by, :id).limit(10).map { |i| line(i.check_name, false, label: i.fund.name) }
    lines << line(tr("owned.details.more", count: total - 10)) if total > 10
    lines
  end

  def tagged_users
    User.where(entity_id: @entity.id, active: true).with_tag(ComplianceNotices::TAG).to_a
        .select { |u| u.tag_list.to_s.split(",").map(&:strip).include?(ComplianceNotices::TAG) }
  end
end
