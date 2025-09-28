class PortfolioCompanyAgent < SupportAgentService
  step :initialize_agent
  # == Core Functions ==
  step :check_last_quarter_kpi_submission
  step :check_document_presence
  step :check_valuations
  step :generate_progress_reports

  private

  # Initializes the agent with the portfolio_company under review.
  # Sets up the shared context including issue tracking hashes.
  #
  # @param ctx [Hash] Trailblazer execution context
  # @param portfolio_company [Investor] record under verification
  def initialize_agent(ctx, portfolio_company:, **)
    super
    # Initialize execution ctx with a single portfolio_company
    # Setup history, logging, or state tracking for this run
    Rails.logger.debug { "[#{self.class.name}] Initializing agent for Investor ID=#{portfolio_company.id}" }
    ctx[:portfolio_company] = portfolio_company
    ctx[:issues] = { kpi_issues: [], document_issues: [], valuation_issues: [] }
    # Only process if completed by investor and agent is enabled
    portfolio_company.category == "Portfolio Company" && @support_agent.enabled?
  end

  # Checks whether the portfolio company has submitted last quarter's KPIs.
  # Adds issues to ctx[:issues][:kpi_issues] if submission is missing, incomplete, or delayed.
  #
  # @param ctx [Hash] Trailblazer execution context
  def check_last_quarter_kpi_submission(ctx, portfolio_company:, **)
    last_kpi_submission_months = @support_agent.json_fields["last_kpi_submission_months"]&.to_i || 3
    # Fetch last quarter KPIs for the portfolio_company
    # Validate submission presence, timeliness, and completeness
    # Append issues to ctx[:issues][:kpi_issues] if problems found
    if portfolio_company.kpi_reports.exists?(as_of: last_kpi_submission_months.months.ago)
      Rails.logger.debug { "[#{self.class.name}] Last quarter KPIs submitted for Investor ID=#{portfolio_company.id}" }
    else
      ctx[:issues][:kpi_issues] << { type: :missing, message: "Last quarter KPIs not submitted", severity: :warning }
      Rails.logger.warn { "[#{self.class.name}] Last quarter KPIs missing for Investor ID=#{portfolio_company.id}" }
    end
    true
  end

  # Verifies if mandatory documents are present for compliance and operational checks.
  # Adds issues to ctx[:issues][:document_issues] if any required documents are missing or invalid.
  def check_document_presence(ctx, portfolio_company:, support_agent:, **)
    last_kpi_report = portfolio_company.kpi_reports.order(as_of: :desc).first
    super(ctx, model: last_kpi_report, support_agent: support_agent)
  end

  # Validates valuations reported for the portfolio_company.
  # Adds issues to ctx[:issues][:valuation_issues] if there are missing valuations, stale entries, or anomalies.
  #
  # @param ctx [Hash] Trailblazer execution context
  def check_valuations(ctx, portfolio_company:, **)
    last_valuation_check_days = @support_agent.json_fields["last_valuation_check_days"]&.to_i || 90
    # Retrieve reported valuations
    # Check for recency, accuracy, and consistency with standards
    # Append issues to ctx[:issues][:valuation_issues] if problems found
    if portfolio_company.valuations.exists?(["valuation_date >= ?", last_valuation_check_days.days.ago])
      Rails.logger.debug { "[#{self.class.name}] Recent valuations found for Investor ID=#{portfolio_company.id}" }
    else
      ctx[:issues][:valuation_issues] << { type: :stale, message: "No valuations in the past #{last_valuation_check_days} days", severity: :warning }
      Rails.logger.warn { "[#{self.class.name}] Stale valuations for Investor ID=#{portfolio_company.id}" }
    end
    true
  end

  # Generates per-investor/fund reports summarizing issues and state.
  # Stores report as persisted SupportAgentReport record.
  def generate_progress_reports(ctx, portfolio_company:, support_agent:, **)
    super(ctx, model: portfolio_company, support_agent: support_agent)
  end
end
