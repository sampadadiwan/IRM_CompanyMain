# ⑩ What's next (Phase 5): at most three actions for the record on the page and the user's role.
# Worked out from the record's state on every view — nothing stored (R153). Every action is kept only if
# the user's own policy allows it, so the panel never offers a button that would be refused.
# Read-only: it links to existing, separately authorized actions.
#
# Worked examples H84, H85, E186, E187, E188 — openspec/changes/archive/2026-11-06-fund-compliance-monitoring/business-rules.md
class ComplianceNextSteps
  MAX_ACTIONS = 3

  # kind: :link (GET), :button (button_to with method), :modal (opens a modal already on the page)
  Action = Struct.new(:label, :path, :http_method, :kind, :target, :icon, :colour, :id, keyword_init: true)
  Panel = Struct.new(:message, :actions, :note, keyword_init: true)

  def self.call(record:, user:, setup: nil, context: {})
    new(record, user, setup, context).call
  end

  def initialize(record, user, setup, context)
    @record = record
    @user = user
    @setup = setup || ComplianceEntitySetup.for(user.entity)
    @context = context
  end

  def call
    panel = case @record
            when ComplianceResult then for_result
            when ComplianceRegisterItem then for_item(@record, on_item_page: true)
            when CompliancePackVersion then for_version
            when :register then for_register
            when :duties then for_duties
            when :facts then for_facts
            end
    return nil unless panel

    panel.actions = Array(panel.actions).compact.first(MAX_ACTIONS)
    panel
  end

  private

  def routes
    Rails.application.routes.url_helpers
  end

  def t(key, **)
    I18n.t("compliance.next.#{key}", **)
  end

  def next_run
    { time: format("%02d:00", ComplianceScheduleJob::RUN_HOUR), zone: Time.current.in_time_zone(@setup.time_zone.presence || "Asia/Kolkata").strftime("%Z") }
  end

  def allowed?(record, query)
    Pundit.policy(@user, record).public_send(query)
  end

  # H84 / H85: a breach offers Assign · Request an explanation (on its register item) or fixing the data;
  # Could not check names the input to map; Needs review points at the facts waiting
  def for_result
    r = @record
    case r.outcome
    when "breach"
      item = ComplianceRegisterItem.open_items.find_by(fund_compliance_pack_id: r.fund_compliance_pack_id, check_key: r.check_key)
      return Panel.new(message: t("breach"), note: t("fix_data")) unless item

      for_item(item, on_item_page: false)
    when "could_not_check"
      missing = r.working_hash["missing"].presence || "the missing input"
      action = if ComplianceAccess.editor?(@user)
                 Action.new(label: "Map #{missing} in Setup", path: routes.compliance_entity_setup_path(anchor: "setup_inputs"), kind: :link,
                            icon: :setup, colour: "primary", id: "next_fix_setup")
               end
      Panel.new(message: t("could_not_check", missing:), actions: [action])
    when "needs_review"
      Panel.new(message: t("needs_review"),
                actions: [Action.new(label: "Facts to confirm", path: routes.document_readings_path, kind: :link, icon: :fact,
                                     colour: "primary", id: "next_facts")])
    else
      Panel.new(message: t("pass"))
    end
  end

  # E186 / E187: an approver is offered Approve / Reject; the requester is told who decides
  def for_item(item, on_item_page:)
    return nil if item.closed?

    req = item.pending_explanation
    return pending_panel(req) if req

    actions = []
    if item.open? && allowed?(item, :assign?)
      actions << item_action(item, "assign", "Assign it", :assign, on_item_page)
      actions << item_action(item, "explain", "Request an explanation", :explain, on_item_page)
    end
    message = item.overdue? ? "#{t('overdue', date: I18n.l(item.fix_by))} #{t('breach')}" : t("breach")
    Panel.new(message:, actions:, note: t("fix_data"))
  end

  def item_action(item, modal, label, icon, on_item_page)
    if on_item_page
      Action.new(label:, kind: :modal, target: "##{modal}ItemModal", icon:, colour: "primary", id: "next_#{modal}")
    else
      Action.new(label:, path: routes.compliance_register_item_path(item, open: modal), kind: :link, icon:, colour: "primary", id: "next_#{modal}")
    end
  end

  def pending_panel(req)
    eligible = ComplianceAccess.eligible_approvers(req.entity)
    can_decide = allowed?(req, :approve?) && (req.requested_by_id != @user.id || eligible.size == 1)
    if can_decide
      Panel.new(message: t("approve", requester: req.requested_by.full_name),
                actions: [Action.new(label: "Approve", path: routes.approve_compliance_request_path(req), http_method: :patch, kind: :button,
                                     icon: :approve, colour: "success", id: "next_approve"),
                          Action.new(label: "Reject", path: routes.reject_compliance_request_path(req), http_method: :patch, kind: :button,
                                     icon: :reject, colour: "danger", id: "next_reject")])
    else
      names = eligible.reject { |u| u.id == req.requested_by_id }.map(&:full_name).to_sentence(two_words_connector: " or ", last_word_connector: " or ")
      Panel.new(message: t("waiting", names: names.presence || "another approver"))
    end
  end

  def for_version
    v = @record
    if v.draft?
      return nil unless allowed?(v, :update?)

      Panel.new(message: t("version_draft"),
                actions: [Action.new(label: "Test run", path: routes.compliance_pack_version_path(v, tab: "version-test-tab"), kind: :link,
                                     icon: :view, colour: "primary", id: "next_test")])
    elsif v.effective_from && v.effective_from > Time.zone.today
      Panel.new(message: t("version_ahead", date: I18n.l(v.effective_from)))
    end
  end

  # E188: an empty register says so and when the next run is
  def for_register
    return nil unless @context[:open_count].to_i.zero?

    Panel.new(message: t("register_empty", **next_run))
  end

  def for_duties
    due = @context[:due_count].to_i
    due.positive? ? Panel.new(message: t("duty_due")) : Panel.new(message: t("nothing", **next_run))
  end

  def for_facts
    @context[:waiting].to_i.positive? ? Panel.new(message: t("facts_waiting")) : Panel.new(message: t("nothing", **next_run))
  end
end
