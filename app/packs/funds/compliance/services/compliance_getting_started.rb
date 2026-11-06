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
# Worked examples H80–H83, E180–E183, E191 — openspec/changes/fund-compliance-monitoring/business-rules.md
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
    step("attach", @fund_packs.any?, path: routes.fund_compliance_packs_path)
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
    tagged = User.where(entity_id: @entity.id, active: true).with_tag(ComplianceNotices::TAG).to_a
                 .any? { |u| u.tag_list.to_s.split(",").map(&:strip).include?(ComplianceNotices::TAG) }
    step("recipients", tagged, path: routes.users_path, can_act: @user.has_cached_role?(:company_admin))
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
end
