# Insight widgets that read fund data for an LP or for the whole firm: Investor Pending Actions (Investor
# Dashboard), Needs Attention (Ops Dashboard, FM Landing Page) and Side-letter Obligations (Investor and Ops
# Dashboards). Worked examples H17–H21, H24, E45–E58, X3, X10 —
# openspec/changes/dashboard-insight-widgets/business-rules.md#6 and #7
module InvestorOpsInsightWidgetsHelper
  # Rows each Investor Pending Actions section lists; the count covers all of them
  PENDING_ACTION_ROWS = 5
  # Remittance statuses that still owe money (Paid and Overpaid are settled)
  OPEN_REMITTANCE_STATUSES = %w[Pending Overdue].freeze

  # One section of Investor Pending Actions: a title, a one-line explanation of what it counts, how many records,
  # the first few, a link to them all, and its table columns as [heading, tooltip or nil, right-aligned?]
  PendingSection = Struct.new(:key, :title, :icon, :help, :total, :rows, :path, :columns, keyword_init: true)
  # One Needs Attention card; help is its tooltip: what it counts and what to do
  AttentionCard = Struct.new(:key, :subtitle, :total, :path, :color, :icon, :help, keyword_init: true)

  # ── Investor Pending Actions ────────────────────────────────────────────────────────────────

  # The four sections for an LP, each one count query plus one rows query (H17).
  def investor_pending_sections(investor, kyc_expiry_days)
    [
      pending_remittances_section(investor),
      pending_kycs_section(investor, kyc_expiry_days),
      pending_approvals_section(investor),
      pending_esign_section(investor)
    ]
  end

  # Unpaid calls: the LP's Pending or Overdue remittances, oldest due date first.
  # X10 — through the remittance policy scope, so a fund the viewer cannot access drops out.
  def pending_remittances_section(investor)
    scope = policy_scope(CapitalRemittance).where(investor_id: investor.id, status: OPEN_REMITTANCE_STATUSES)
    # The first rows with the fund and call they display preloaded (no query per row)
    rows = scope.joins(:capital_call).includes(:fund, :capital_call)
                .order("capital_calls.due_date ASC, capital_remittances.id ASC").limit(PENDING_ACTION_ROWS).to_a
    PendingSection.new(key: :remittances, title: "Unpaid calls", icon: "ti ti-cash", total: scope.count, rows:,
                       help: "Capital calls this LP has not paid in full (Pending or Overdue), oldest due date first.",
                       columns: [["Call", "The capital call, with its fund below", false],
                                 ["Due date", "The date the call asked to be paid by", false],
                                 ["Status", "Overdue: past the due date. Pending: not yet due, or due today", false],
                                 ["Due", "Call amount + other fees − amount already collected", true]],
                       path: capital_remittances_path(status: OPEN_REMITTANCE_STATUSES.join(","),
                                                      q: ransack_query_params("investor_name", :eq, investor.investor_name)))
  end

  # KYCs that are not verified, or that expire within kyc_expiry_days or have expired (E45, E46)
  def pending_kycs_section(investor, kyc_expiry_days)
    base = policy_scope(InvestorKyc).where(investor_id: investor.id)
    # Not verified, OR expiring on or before the warning date (an expired KYC is before it too)
    warn_on = Time.zone.today + kyc_expiry_days.days
    scope = base.where(verified: false).or(base.where(expiry_date: ..warn_on))
    # The KYC scope may join access rights for some roles, so dedupe in SQL (KycSearch does the same)
    rows = scope.distinct.order(:expiry_date, :id).limit(PENDING_ACTION_ROWS).to_a
    PendingSection.new(key: :kycs, title: "KYC", icon: "ti ti-id-badge", total: scope.distinct.count(:id), rows:,
                       help: "KYCs not verified yet, or verified but expired or expiring within #{kyc_expiry_days} days.",
                       columns: [["KYC", "The name on the KYC record", false],
                                 ["Outstanding", "Not verified: open it and verify. Expired / Expires: ask the LP for a refreshed KYC", true]],
                       path: investor_kycs_path(investor_id: investor.id))
  end

  # What a KYC row says is outstanding: not verified, expired or expiring (E45)
  def pending_kyc_reason(kyc)
    return "Not verified" unless kyc.verified
    return "Expired #{l(kyc.expiry_date)}" if kyc.expiry_date < Time.zone.today

    "Expires #{l(kyc.expiry_date)}"
  end

  # Approval responses still Pending, on approvals that are published and not past due (E47)
  def pending_approvals_section(investor)
    scope = policy_scope(ApprovalResponse).where(investor_id: investor.id, status: "Pending")
                                          .joins(:approval)
                                          .where(approvals: { approved: true, due_date: Time.zone.today.. })
    rows = scope.includes(:approval).order("approvals.due_date ASC").limit(PENDING_ACTION_ROWS).to_a
    PendingSection.new(key: :approvals, title: "Approvals awaiting reply", icon: "ti ti-checkbox", total: scope.count,
                       rows:, path: approvals_path,
                       help: "Published approvals this LP has not replied to, whose reply date has not passed.",
                       columns: [["Approval", nil, false],
                                 ["Reply by", "The approval's due date; after it the request closes", true]])
  end

  # Documents still awaiting e-signature that belong to the LP's commitments or KYCs (E48 — completed left out)
  def pending_esign_section(investor)
    open = policy_scope(Document).where(esign_status: Document::ESIGN_ACTIVE_STATUSES)
    # Owned by one of this LP's commitments, or one of its KYCs (subqueries, not plucked ids)
    scope = open.where(owner_type: "CapitalCommitment", owner_id: investor.capital_commitments.select(:id))
                .or(open.where(owner_type: "InvestorKyc", owner_id: investor.investor_kycs.select(:id)))
    # documents is a large table with wide columns: count in SQL and load only what a row shows (plus the four
    # flags Document#init defaults on load, which raise MissingAttributeError when not selected)
    rows = scope.select(:id, :name, :esign_status, :sent_for_esign_date, :send_email, :approved, :template, :sent_for_esign)
                .order(:sent_for_esign_date, :id)
                .limit(PENDING_ACTION_ROWS).to_a
    PendingSection.new(key: :esign, title: "Awaiting e-signature", icon: "ti ti-signature", total: scope.count, rows:,
                       path: investor_path(investor),
                       help: "Commitment and KYC documents sent to this LP for e-signature and not fully signed yet.",
                       columns: [["Document", nil, false],
                                 ["E-sign status", "Requested, sent or in progress, and the date it was sent for signing", true]])
  end

  # ── Needs Attention ─────────────────────────────────────────────────────────────────────────

  # The four cards, each count equal to the rows its link shows (H19, H21). A card is left out when the
  # viewer may not open its list at all (the same check the list's index action makes).
  # B16 — no "Imports with errors" card: removed on request (2026-11-07)
  def needs_attention_cards
    cards = []
    cards << overdue_tasks_card if policy(Task).index?
    cards << kycs_to_verify_card if policy(InvestorKyc).index?
    cards << overdue_remittances_card if policy(CapitalRemittance).index?
    cards << open_esign_card if policy(Document).index?
    cards
  end

  # Open tasks due before today (E54 — due today is not overdue); the tasks list shows only open tasks by default
  def overdue_tasks_card
    count = policy_scope(Task).where(completed: false).where(due_date: ...Time.zone.today).count
    AttentionCard.new(key: :tasks, subtitle: "Overdue tasks", total: count, color: "danger", icon: "ti ti-clock-stop",
                      help: "Open tasks whose due date was before today. Click to see them and reassign or close them.",
                      path: tasks_path(q: ransack_query_params("due_date", :lt, Time.zone.today)))
  end

  # KYCs the investor submitted that nobody has verified yet (E55 — not sent / link sent are not counted)
  def kycs_to_verify_card
    count = policy_scope(InvestorKyc).where(verified: false, submission_status: "completed").distinct.count(:id)
    AttentionCard.new(key: :kycs, subtitle: "KYCs to verify", total: count, color: "warning", icon: "ti ti-id-badge",
                      help: "KYCs the investor has submitted that nobody has verified yet. Click to review and verify them.",
                      path: investor_kycs_path(verified: "false",
                                               q: ransack_query_params("submission_status", :eq, "completed")))
  end

  # Remittances whose status is Overdue (H21 — the list filtered by the same status)
  def overdue_remittances_card
    count = policy_scope(CapitalRemittance).where(status: "Overdue").count
    AttentionCard.new(key: :remittances, subtitle: "Overdue remittances", total: count, color: "danger", icon: "ti ti-cash",
                      help: "Capital call remittances past their due date and not fully paid. Click to follow up with the investors.",
                      path: capital_remittances_path(status: "Overdue"))
  end

  # E-sign requests still requested, sent or in progress (E57 — failed and cancelled are not open)
  def open_esign_card
    scope = policy_scope(Document).where(esign_status: Document::ESIGN_ACTIVE_STATUSES)
    # The documents list shows a non-admin only the documents they uploaded, so count the same way
    scope = scope.where(user_id: current_user.id) unless current_user.has_cached_role?(:company_admin)
    AttentionCard.new(key: :esign, subtitle: "Open e-sign requests", total: scope.count, color: "info",
                      help: "Documents sent for e-signature (requested, sent or in progress) and not fully signed. Click to chase signers.",
                      icon: "ti ti-signature",
                      # entity_id: the e-signatures page builds its stats cards per fund / sale / entity and errors
                      # without one; the list itself is already limited to the user's entity by policy_scope
                      path: documents_path(entity_id: current_user.entity_id, no_folders: true, template: "/e_signatures/e_signatures",
                                           q: ransack_query_params_multiple([["esign_status", "in", Document::ESIGN_ACTIVE_STATUSES]])))
  end

  # ── Side-letter Obligations ─────────────────────────────────────────────────────────────────

  # Active, approved obligations due within `days` or overdue, earliest (so overdue) first. With an investor
  # only that LP's obligations (H18); without, all the viewer may see (H24). Returns [rows, total].
  # E51 — 30 days in, 31 days out; E52 — overdue listed first; E53 — fulfilled, waived and unreviewed left out.
  def side_letter_obligations_due(days, investor: nil, limit: 10)
    scope = policy_scope(SideLetterObligation).obligation_active.where(review_status: "approved")
                                              .where(next_due_date: ..(Time.zone.today + days.days))
    # Investor Dashboard: only obligations of side letters on this LP's commitments
    scope = scope.joins(side_letter: :capital_commitment).where(capital_commitments: { investor_id: investor.id }) if investor
    # The rows, with the commitment, fund and owner they display preloaded
    rows = scope.includes(:owner_user, side_letter: { capital_commitment: :fund })
                .order(:next_due_date, :id).limit(limit).to_a
    [rows, scope.count]
  end
end
