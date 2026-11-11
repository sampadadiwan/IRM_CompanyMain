# frozen_string_literal: true

# Query object that encapsulates report-loading logic for the different
# SupportAgent types displayed on the SupportAgent show page.
#
# Each agent type surfaces a different category of SupportAgentReport scoped
# by owner_type, ordered by a relevant timestamp column, and optionally
# filtered to a specific owner via +owner_id+.
#
# @example
#   query = AgentReportsQuery.new(@support_agent, params)
#   @fund_reports         = query.fund_reports
#   @portfolio_reports    = query.portfolio_reports
class AgentReportsQuery
  # @param support_agent [SupportAgent] the agent whose reports to load
  # @param params [Hash, ActionController::Parameters] request params (may contain +owner_id+)
  def initialize(support_agent, params = {})
    @support_agent = support_agent
    @params = params || {}
  end

  # Reports scoped to +Fund+ owners (CashFlowAssistantAgent only).
  # @return [ActiveRecord::Relation<SupportAgentReport>]
  def fund_reports
    return SupportAgentReport.none unless agent_type?("CashFlowAssistantAgent")

    agent_reports("Fund").order(updated_at: :desc)
  end

  # Reports scoped to +Investor+ owners (PortfolioCompanyAgent only).
  # @return [ActiveRecord::Relation<SupportAgentReport>]
  def portfolio_reports
    return SupportAgentReport.none unless agent_type?("PortfolioCompanyAgent")

    apply_owner_filter(agent_reports("Investor")).order(updated_at: :desc)
  end

  # Reports scoped to +Investor+ owners (PortfolioScoringAgent only).
  # Surfaces both successful runs ("score" key) and failed runs ("error" key) —
  # filtering to "score" only would hide every failure from the UI. Step-tracking
  # reports are excluded via their "steps" key, which scoring reports never have.
  # @return [ActiveRecord::Relation<SupportAgentReport>]
  def scoring_reports
    return SupportAgentReport.none unless agent_type?("PortfolioScoringAgent")

    apply_owner_filter(agent_reports("Investor"))
      .where("(json_fields LIKE '%\"score\":%' OR json_fields LIKE '%\"error\":%') AND json_fields NOT LIKE '%\"steps\":%'")
      .order(created_at: :desc)
  end

  # Reports scoped to +Investor+ owners (NoteSummarizerAgent only).
  # @return [ActiveRecord::Relation<SupportAgentReport>]
  def note_summaries
    return SupportAgentReport.none unless agent_type?("NoteSummarizerAgent")

    apply_owner_filter(agent_reports("Investor")).order(updated_at: :desc)
  end

  # Reports scoped to +Investor+ owners (PresentationAnalystAgent only).
  # @return [ActiveRecord::Relation<SupportAgentReport>]
  def presentation_reports
    return SupportAgentReport.none unless agent_type?("PresentationAnalystAgent")

    apply_owner_filter(agent_reports("Investor")).order(created_at: :desc)
  end

  # Reports scoped to +Deal+ owners (DealsReportAgent only).
  # @return [ActiveRecord::Relation<SupportAgentReport>]
  def deal_reports
    return SupportAgentReport.none unless agent_type?("DealsReportAgent") || agent_type?("DealManagementAgent")

    agent_reports("Deal").order(updated_at: :desc)
  end

  # Reports scoped to +Fund+ owners (RtaReconciliationAgent only).
  # Excludes the bare progress-tracking row (one per fund, reused/overwritten on
  # every run to drive the live step panel) — only rows carrying actual
  # reconciliation results (one new row per run) should show as history.
  # @return [ActiveRecord::Relation<SupportAgentReport>]
  def rta_reports
    return SupportAgentReport.none unless agent_type?("RtaReconciliationAgent")

    agent_reports("Fund").where("json_fields LIKE '%\"scheme_results\":%'").order(updated_at: :desc).limit(50)
  end

  # The Obligations tab for SideLetterObligationAgent and CpCsExtractionAgent
  # shows the obligations themselves (the LP Obligation Matrix), not
  # SupportAgentReports — the matrix IS the agent's living output.
  # CpCsExtractionAgent scopes to portfolio investment obligations only.
  # Optional owner_id narrows to one commitment or investment.
  # @return [ActiveRecord::Relation<SideLetterObligation>]
  def side_letter_obligations
    return SideLetterObligation.none unless agent_type?("SideLetterObligationAgent") || agent_type?("CpCsExtractionAgent")

    scope = SideLetterObligation.where(entity_id: @support_agent.entity_id)
                                .order(Arel.sql("next_due_date IS NULL, next_due_date ASC"))

    if agent_type?("CpCsExtractionAgent")
      scope = scope.where(sourceable_type: "PortfolioInvestment")
                   .includes(:owner_user, :sourceable)
      scope = scope.where(sourceable_id: @params[:owner_id]) if @params[:owner_id].present?
    else
      scope = scope.includes(:owner_user, side_letter: { capital_commitment: %i[investor fund] })
      scope = scope.joins(:side_letter).where(side_letters: { capital_commitment_id: @params[:owner_id] }) if @params[:owner_id].present?
    end

    scope
  end

  # Aggregates all KYC dashboard data in a single call: basic form-status
  # metrics, per-type agent stat counts (used for both stat cards and charts),
  # top failure reasons, paginated records, and document ratios.
  # Used by the KYC Dashboard tab on the KycOnboardingAgent show page.
  #
  # @param filter_params [Hash] optional filter keys: :status, :kyc_type, :q, :fund_id,
  #   :date_from, :date_to, :page
  # @return [Hash] { basic_stats: Hash, type_stats: Hash, top_failures: Array,
  #   records: Array<InvestorKyc>, pagy: Pagy, doc_ratios: Hash, pending_ids: Array }
  def kyc_dashboard_data(filter_params = {})
    return empty_kyc_dashboard unless agent_type?("KycOnboardingAgent")

    basic      = kyc_basic_stats
    type_stats = kyc_type_stats
    failures   = kyc_top_failures
    pagy, records = kyc_filtered_records(filter_params)
    doc_ratios = kyc_doc_ratios(records)

    { basic_stats: basic, type_stats: type_stats,
      records: records, pagy: pagy, top_failures: failures,
      doc_ratios: doc_ratios, pending_ids: kyc_pending_ids }
  end

  # Counts ALL entity KYCs for the basic metrics row (Row 1), matching
  # the same scopes used by the normal KYC index page stat cards.
  # Uses individual count queries on boolean/date/enum fields — same
  # approach as _stats.html.erb in investor_kycs views.
  #
  # @return [Hash] { verified: Integer, unverified: Integer,
  #   completed: Integer, expired: Integer, individual: Integer,
  #   non_individual: Integer }
  def kyc_basic_stats
    base = InvestorKyc.where(entity_id: @support_agent.entity_id)

    # Submission status counts (product-requested basic metrics)
    status_counts = base.group(:submission_status).count

    { not_sent: status_counts["not_sent"].to_i,
      link_sent: status_counts["link_sent"].to_i,
      draft_saved: status_counts["draft_saved"].to_i,
      completed: status_counts["completed"].to_i,
      verified_status: status_counts["verified"].to_i,
      # Existing scope-based metrics
      verified: base.verified.count,
      unverified: base.unverified.count,
      completed_scope: base.completed.count,
      expired: base.expired.count,
      individual: base.individual.count,
      non_individual: base.non_individual.count }
  end

  # SQL fragment: true when a KYC is NOT expired (expiry_date null or in the future).
  # Used across stat counts, chart data, and status filters to make expired mutually exclusive.
  KYC_NOT_EXPIRED = "(investor_kycs.expiry_date IS NULL OR investor_kycs.expiry_date >= CURDATE())"

  # JSON_SEARCH fragments for Failed vs Partially Failed classification.
  # LIKE fails on native MySQL JSON columns (binary storage); JSON_SEARCH
  # operates on the parsed structure and matches reliably.
  HAS_SUCCESS_SEVERITY = "JSON_SEARCH(sar.json_fields, 'one', 'success', NULL, '$**.severity') IS NOT NULL"
  NO_SUCCESS_SEVERITY  = "JSON_SEARCH(sar.json_fields, 'one', 'success', NULL, '$**.severity') IS NULL"
  HAS_INFO_TYPE        = "JSON_SEARCH(sar.json_fields, 'one', 'info', NULL, '$**.type') IS NOT NULL"
  NO_INFO_TYPE         = "JSON_SEARCH(sar.json_fields, 'one', 'info', NULL, '$**.type') IS NULL"

  # Computes per-KYC-type (Individual / Non-Individual) stat card counts AND
  # chart data in a single SQL query with GROUP BY type. Each type gets all six
  # stat values: validated, pending, successful, failed, partial, expired.
  # Expired is mutually exclusive — the other four exclude expired KYCs, so
  # pending + successful + failed + partial + expired = validated.
  #
  # @return [Hash] { individual: Hash, non_individual: Hash }
  #   Each inner hash: { validated:, pending:, successful:, failed:, partial:, expired: }
  def kyc_type_stats
    sql = <<~SQL.squish
      SELECT
        investor_kycs.type                                                         AS kyc_type,
        COUNT(*)                                                                   AS validated,
        SUM(CASE WHEN sar.id IS NULL
                  AND #{KYC_NOT_EXPIRED}
                 THEN 1 ELSE 0 END)                                                AS pending,
        SUM(CASE WHEN JSON_UNQUOTE(JSON_EXTRACT(sar.json_fields, '$.final_status')) = 'ready'
                  AND #{KYC_NOT_EXPIRED}
                 THEN 1 ELSE 0 END)                                                AS successful,
        SUM(CASE WHEN ((JSON_UNQUOTE(JSON_EXTRACT(sar.json_fields, '$.final_status')) = 'blocked'
                        AND #{NO_SUCCESS_SEVERITY}
                        AND #{NO_INFO_TYPE})
                       OR JSON_UNQUOTE(JSON_EXTRACT(sar.json_fields, '$.final_status')) = 'error')
                  AND #{KYC_NOT_EXPIRED}
                 THEN 1 ELSE 0 END)                                                AS failed,
        SUM(CASE WHEN JSON_UNQUOTE(JSON_EXTRACT(sar.json_fields, '$.final_status')) = 'blocked'
                  AND (#{HAS_SUCCESS_SEVERITY}
                       OR #{HAS_INFO_TYPE})
                  AND #{KYC_NOT_EXPIRED}
                 THEN 1 ELSE 0 END)                                                AS partial,
        SUM(CASE WHEN investor_kycs.expiry_date < CURDATE() THEN 1 ELSE 0 END)    AS expired
      FROM investor_kycs
      LEFT JOIN support_agent_reports AS sar
        ON sar.owner_type  = 'InvestorKyc'
        AND sar.owner_id   = investor_kycs.id
        AND sar.latest     = true
        AND sar.support_agent_id = :agent_id
      WHERE investor_kycs.entity_id = :entity_id
        AND investor_kycs.submission_status = 'completed'
        AND investor_kycs.deleted_at IS NULL
      GROUP BY investor_kycs.type
    SQL

    rows = ActiveRecord::Base.connection.select_all(
      ActiveRecord::Base.sanitize_sql_array(
        [sql, { agent_id: @support_agent.id, entity_id: @support_agent.entity_id }]
      )
    )

    result = { individual: empty_type_stats, non_individual: empty_type_stats }
    rows.each do |row|
      key = row["kyc_type"] == "IndividualKyc" ? :individual : :non_individual
      result[key] = {
        validated: row["validated"].to_i,
        pending: row["pending"].to_i,
        successful: row["successful"].to_i,
        failed: row["failed"].to_i,
        partial: row["partial"].to_i,
        expired: row["expired"].to_i
      }
    end
    result
  end

  # Extracts the top N most common blocking issues from all latest reports
  # for this agent's entity. Plucks json_fields + owner_id and aggregates in
  # Ruby because the issues are nested JSON arrays not easily grouped in
  # MySQL < 8.0. Also collects affected KYC IDs per failure reason, then
  # batch-loads investor names (one query) to avoid N+1.
  #
  # @param limit [Integer] max number of failure reasons to return
  # @return [Array<Hash>] [{ message: String, count: Integer,
  #   affected: [{ kyc_id: Integer, investor_name: String }] }] sorted desc by count
  def kyc_top_failures(limit: 5)
    filter = { support_agent_id: @support_agent.id, owner_type: "InvestorKyc", latest: true }
    reports = SupportAgentReport.where(filter)
                                .where("JSON_SEARCH(json_fields, 'one', 'blocking', NULL, '$.field_issues[*].severity') IS NOT NULL " \
                                       "OR JSON_SEARCH(json_fields, 'one', 'blocking', NULL, '$.document_issues[*].severity') IS NOT NULL")
                                .pluck(:owner_id, :json_fields)

    # { label => Set<kyc_id> } — tracks which KYCs are affected by each failure
    affected_map = Hash.new { |h, k| h[k] = Set.new }
    reports.each do |owner_id, json_str|
      parsed = json_str.is_a?(String) ? JSON.parse(json_str) : json_str
      (parsed["field_issues"].to_a + parsed["document_issues"].to_a).each do |issue|
        next unless issue["severity"] == "blocking"

        affected_map[failure_label(issue)] << owner_id
      end
    rescue JSON::ParserError
      next
    end

    top = affected_map.sort_by { |_, ids| -ids.size }.first(limit)
    return [] if top.empty?

    # Batch-load KYC names for all affected KYC IDs (single query, no N+1)
    all_kyc_ids = top.flat_map { |_, ids| ids.to_a }.uniq
    kyc_names = InvestorKyc.where(id: all_kyc_ids)
                           .left_joins(:investor)
                           .pluck(:id, :full_name, "investors.investor_name")
                           .to_h { |id, full_name, inv_name| [id, full_name.presence || inv_name || "Unknown"] }

    top.map do |message, kyc_ids|
      { message: message,
        count: kyc_ids.size,
        affected: kyc_ids.map { |id| { kyc_id: id, kyc_name: kyc_names[id] || "Unknown" } } }
    end
  end

  # Returns a paginated, filtered collection of completed InvestorKycs for
  # the dashboard table. Eager-loads :investor (for name column) and
  # :support_agent_report (for status/result columns) to prevent N+1.
  #
  # @param filter_params [Hash] :status, :kyc_type, :q, :fund_id,
  #   :date_from, :date_to, :page
  # @return [Array(Pagy, Array<InvestorKyc>)]
  def kyc_filtered_records(filter_params = {})
    scope = kyc_base_scope.includes(:investor, :support_agent_report)
    scope = apply_kyc_filters(scope, filter_params)

    Pagy.new(count: scope.count, page: (filter_params[:page] || 1).to_i, limit: 5)
        .then { |pagy| [pagy, scope.offset(pagy.offset).limit(pagy.limit).order(created_at: :desc).to_a] }
  end

  # Computes document upload ratios with names for the Docs column tooltip.
  # Returns uploaded/required counts plus required, uploaded, and missing doc
  # names per KYC. Uses the same name-matching logic as InvestorKycConcern
  # (label.presence || name.humanize, normalized prefix stripping).
  # Two bulk queries (FormCustomField + Document) to avoid N+1.
  #
  # @param records [Array<InvestorKyc>] already-loaded KYC records (with form_type_id)
  # @return [Hash<Integer, Hash>] { kyc_id => { uploaded:, required:,
  #   required_names:, uploaded_names:, missing_names: } }
  def kyc_doc_ratios(records)
    return {} if records.blank?

    kyc_ids = records.map(&:id)
    form_type_ids = records.filter_map(&:form_type_id).uniq

    # Required doc names per form_type_id (from File-type required custom fields)
    required_by_form_type = FormCustomField
                            .where(form_type_id: form_type_ids, field_type: "File", required: true)
                            .pluck(:form_type_id, :label, :name)
                            .group_by(&:first)
                            .transform_values { |rows| rows.map { |_, label, name| label.presence || name.to_s.humanize } }

    # Uploaded doc names per KYC
    uploaded_by_kyc = Document
                      .where(owner_type: "InvestorKyc", owner_id: kyc_ids)
                      .pluck(:owner_id, :name)
                      .group_by(&:first)
                      .transform_values { |rows| rows.map(&:last) }

    records.each_with_object({}) do |kyc, hash|
      req_names = required_by_form_type[kyc.form_type_id] || []
      upl_names = uploaded_by_kyc[kyc.id] || []

      # Missing = required names not matched by any uploaded doc (normalized)
      upl_normalized = upl_names.to_set { |n| normalize_doc_name(n) }
      missing = req_names.reject { |n| upl_normalized.include?(normalize_doc_name(n)) }

      hash[kyc.id] = {
        uploaded: upl_names.size, required: req_names.size,
        required_names: req_names, uploaded_names: upl_names,
        missing_names: missing
      }
    end
  end

  # Strips common prefixes ("Upload ", "Attach your ", "Attach ") and
  # downcases for name comparison — mirrors InvestorKycConcern logic.
  #
  # @param name [String, nil]
  # @return [String]
  def normalize_doc_name(name)
    name.to_s.strip.sub(/\A(upload|attach your|attach)\s+/i, "").downcase
  end

  # Returns IDs of completed KYCs that have no latest report from this agent
  # (i.e., "pending" KYCs). Used by the bulk run button to pass target_ids
  # to the run_batch action.
  #
  # @return [Array<Integer>]
  def kyc_pending_ids
    kyc_base_scope
      .where.not(
        id: SupportAgentReport.where(support_agent: @support_agent, owner_type: "InvestorKyc", latest: true).select(:owner_id)
      )
      .pluck(:id)
  end

  # Acronyms to upcase when humanizing failure reason messages.
  FAILURE_ACRONYMS = %w[ifsc pan gstin cin din llpin upi nri aml kyc].freeze

  private

  # Builds a readable label from a blocking issue hash. Field issues with
  # type "invalid_field_value" get "Missing <Field Name>"; document issues
  # already have descriptive messages like "Invalid Address".
  def failure_label(issue)
    field = issue["message"].underscore.humanize.titleize
    label = case issue["type"]
            when "invalid_field_value" then "Missing #{field}"
            when "invalid" then "Invalid #{field}"
            when "mismatched_document" then "Wrong Document: #{issue['name'] || field}"
            when "missing" then "Missing Document: #{issue['name'] || field}"
            else issue["message"]
            end
    FAILURE_ACRONYMS.each { |a| label.gsub!(/\b#{a}\b/i, a.upcase) }
    label
  end

  # Checks whether the current support agent matches a given type.
  def agent_type?(type)
    @support_agent.agent_type == type
  end

  # Returns a base scope of reports for the given +owner_type+.
  def agent_reports(owner_type)
    SupportAgentReport
      .where(support_agent: @support_agent, owner_type: owner_type)
      .includes(:owner)
  end

  # Applies an +owner_id+ filter when the +owner_id+ param is present.
  def apply_owner_filter(scope)
    return scope if @params[:owner_id].blank?

    scope.where(owner_id: @params[:owner_id])
  end

  # Base scope: submitted KYCs in the agent's entity. Single source of truth
  # for entity scoping across all KYC dashboard queries.
  #
  # @return [ActiveRecord::Relation<InvestorKyc>]
  # Uses submission_status (enum) — only "completed" KYCs; verified ones are already reviewed.
  def kyc_base_scope
    InvestorKyc.where(entity_id: @support_agent.entity_id, submission_status: "completed")
  end

  # Applies dashboard filter params to a KYC scope. Each filter is optional
  # and they combine with AND logic. Status filter delegates to
  # +apply_kyc_status_filter+ for the LEFT JOIN logic. kyc_type filters by
  # STI type (IndividualKyc / NonIndividualKyc) for the two-column layout.
  #
  # @param scope [ActiveRecord::Relation<InvestorKyc>]
  # @param params [Hash] :status, :kyc_type, :q, :fund_id, :date_from, :date_to
  # @return [ActiveRecord::Relation<InvestorKyc>]
  def apply_kyc_filters(scope, params)
    scope = scope.where(type: params[:kyc_type]) if params[:kyc_type].present?
    scope = scope.where(investor_kycs: { created_at: (params[:date_from]).. }) if params[:date_from].present?
    scope = scope.where(investor_kycs: { created_at: ..Date.parse(params[:date_to].to_s).end_of_day }) if params[:date_to].present?

    if params[:q].present?
      q = "%#{ActiveRecord::Base.sanitize_sql_like(params[:q])}%"
      scope = scope.joins(:investor)
                   .where("investor_kycs.id LIKE :q OR investors.investor_name LIKE :q OR investor_kycs.PAN LIKE :q", q: q)
    end

    if params[:fund_id].present?
      scope = scope.where(
        "investor_kycs.id IN (SELECT investor_kyc_id FROM capital_commitments WHERE fund_id = ?)",
        params[:fund_id]
      )
    end

    scope = apply_kyc_status_filter(scope, params[:status]) if params[:status].present?
    scope
  end

  # Filters KYCs by dashboard status bucket. Each status requires a different
  # WHERE clause because the classification is derived from the report's
  # json_fields, not a stored column. Expired is mutually exclusive: all
  # non-expired status filters exclude expired KYCs.
  #
  # @param scope [ActiveRecord::Relation<InvestorKyc>]
  # @param status [String] one of "pending", "successful", "failed", "partial", "expired"
  # @return [ActiveRecord::Relation<InvestorKyc>]
  def apply_kyc_status_filter(scope, status)
    return scope.where("investor_kycs.expiry_date < CURDATE()") if status == "expired"

    # All non-expired statuses exclude expired KYCs
    scope = scope.where(KYC_NOT_EXPIRED)

    joined = scope.joins(
      "LEFT JOIN support_agent_reports AS sar " \
      "ON sar.owner_type = 'InvestorKyc' " \
      "AND sar.owner_id = investor_kycs.id " \
      "AND sar.latest = true " \
      "AND sar.support_agent_id = #{ActiveRecord::Base.connection.quote(@support_agent.id)}"
    )

    case status
    when "pending"
      joined.where("sar.id IS NULL") # rubocop:disable Rails/WhereEquals -- sar is a SQL alias, not an AR table
    when "successful"
      joined.where("JSON_UNQUOTE(JSON_EXTRACT(sar.json_fields, '$.final_status')) = 'ready'")
    when "failed"
      joined.where(
        "(JSON_UNQUOTE(JSON_EXTRACT(sar.json_fields, '$.final_status')) = 'blocked' " \
        "AND JSON_SEARCH(sar.json_fields, 'one', 'success', NULL, '$**.severity') IS NULL " \
        "AND JSON_SEARCH(sar.json_fields, 'one', 'info', NULL, '$**.type') IS NULL) " \
        "OR JSON_UNQUOTE(JSON_EXTRACT(sar.json_fields, '$.final_status')) = 'error'"
      )
    when "partial"
      joined.where(
        "JSON_UNQUOTE(JSON_EXTRACT(sar.json_fields, '$.final_status')) = 'blocked' " \
        "AND (JSON_SEARCH(sar.json_fields, 'one', 'success', NULL, '$**.severity') IS NOT NULL " \
        "OR JSON_SEARCH(sar.json_fields, 'one', 'info', NULL, '$**.type') IS NOT NULL)"
      )
    else
      scope
    end
  end

  # Returns a zero-filled dashboard hash for non-KYC agents or empty entities.
  #
  # @return [Hash]
  def empty_kyc_dashboard
    { basic_stats: { not_sent: 0, link_sent: 0, draft_saved: 0, completed: 0, verified_status: 0,
                     verified: 0, unverified: 0, completed_scope: 0, expired: 0, individual: 0, non_individual: 0 },
      type_stats: { individual: empty_type_stats, non_individual: empty_type_stats },
      records: [], pagy: nil, top_failures: [], doc_ratios: {},
      pending_ids: [] }
  end

  # Returns a zero-filled per-type stats hash (stat cards + chart data).
  #
  # @return [Hash]
  def empty_type_stats
    { validated: 0, pending: 0, successful: 0, failed: 0, partial: 0, expired: 0 }
  end
end
