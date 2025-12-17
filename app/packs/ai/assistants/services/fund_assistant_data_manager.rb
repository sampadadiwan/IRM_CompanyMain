# FundAssistantDataManager
#
# Handles the business logic and data retrieval for the FundAssistant.
# This class contains the implementation of the actions exposed by the assistant's tools.
# It uses Pundit policies to ensure the user only accesses authorized data and
# Ransack for flexible querying.
#
class FundAssistantDataManager
  # Query object for filtering CapitalRemittances.
  class CapitalRemittanceQuery
    include HasScope

    has_scope :paid, type: :boolean
    has_scope :pending, type: :boolean
    has_scope :verified, type: :boolean
    has_scope :unverified, type: :boolean

    def perform(collection:, params:)
      apply_scopes(collection, params)
    end
  end

  # Query object for filtering Funds.
  class FundQuery
    include HasScope

    has_scope :feeder_funds, type: :boolean
    has_scope :master_funds, type: :boolean

    def perform(collection:, params:)
      apply_scopes(collection, params)
    end
  end

  # Query object for filtering CapitalCommitments.
  class CapitalCommitmentQuery
    include HasScope

    has_scope :lp_onboarding_complete, type: :boolean
    has_scope :lp_onboarding_incomplete, type: :boolean

    def perform(collection:, params:)
      apply_scopes(collection, params)
    end
  end

  # Query object for filtering PortfolioInvestments.
  class PortfolioInvestmentQuery
    include HasScope

    has_scope :buys, type: :boolean
    has_scope :sells, type: :boolean
    has_scope :conversions, type: :boolean
    has_scope :distributed, type: :boolean
    has_scope :not_distributed, type: :boolean
    has_scope :proforma, type: :boolean
    has_scope :non_proforma, type: :boolean

    def perform(collection:, params:)
      apply_scopes(collection, params)
    end
  end

  # Query object for filtering CapitalDistributionPayments.
  class CapitalDistributionPaymentQuery
    include HasScope

    has_scope :completed, type: :boolean
    has_scope :incomplete, type: :boolean
    has_scope :notification_sent, type: :boolean
    has_scope :notification_not_sent, type: :boolean

    def perform(collection:, params:)
      apply_scopes(collection, params)
    end
  end

  # Initializes the data manager.
  #
  # @param user [User] The user context for data retrieval.
  def initialize(user:)
    @user = user
  end

  # Lists funds based on filters.
  #
  # @param scope [String, nil] Predefined scope name (e.g., 'master_funds').
  # @param query [Hash] Ransack query parameters.
  # @param sort [String, nil] Sort string (e.g., 'name asc').
  # @return [Array<Hash>] List of fund data.
  def list_funds(scope: nil, query: {}, sort: nil)
    ransack_query = query || {}
    ransack_query[:s] ||= sort if sort.present?

    relation = Pundit.policy_scope(@user, Fund)

    # Use HasScope to apply filters safely
    scope_params = scope.present? ? { scope => true } : {}
    relation = FundQuery.new.perform(collection: relation, params: scope_params)

    funds = relation.ransack(ransack_query).result
    funds.map do |f|
      {
        id: f.id,
        name: f.name,
        currency: f.currency,
        unit_types: f.unit_types,
        first_close_date: f.first_close_date,
        last_close_date: f.last_close_date,
        tracking_currency: f.tracking_currency,
        collected_amount: f.collected_amount.format,
        committed_amount: f.committed_amount.format,
        distribution_amount: f.distribution_amount.format,
        call_amount: f.call_amount.format
      }
    end
  end

  # Retrieves detailed information for a specific fund.
  #
  # @param fund_id [Integer] ID of the fund.
  # @return [Hash, String] Fund details or error message if not found/denied.
  def get_fund_details(fund_id:)
    fund = Pundit.policy_scope(@user, Fund).find_by(id: fund_id)
    return "Fund not found or access denied" unless fund

    details = {
      id: fund.id,
      name: fund.name,
      entity: fund.entity&.name,
      currency: fund.currency,
      unit_types: fund.unit_types,
      tags: fund.tag_list.to_s,
      details: fund.details,
      first_close_date: fund.first_close_date,
      last_close_date: fund.last_close_date,
      signatory_emails: fund.esign_emails
    }

    details[:master_fund] = fund.master_fund&.name if fund.master_fund_id.present?

    if fund.has_tracking_currency?
      details[:tracking_currency] = {
        currency: fund.tracking_currency,
        committed: fund.tracking_committed_amount.format,
        call_amount: fund.tracking_call_amount.format,
        collected: fund.tracking_collected_amount.format,
        distributed: fund.tracking_distribution_amount.format
      }
    end

    details
  end

  # Lists capital calls for a fund.
  #
  # @param fund_id [Integer] ID of the fund.
  # @param query [Hash] Ransack query parameters.
  # @param sort [String, nil] Sort string.
  # @return [Array<Hash>] List of capital calls.
  def list_capital_calls(fund_id:, query: {}, sort: nil)
    ransack_query = query || {}
    ransack_query[:s] ||= sort if sort.present?
    ransack_query[:fund_id_eq] = fund_id

    calls = Pundit.policy_scope(@user, CapitalCall).ransack(ransack_query).result
    calls.map do |c|
      {
        id: c.id,
        name: c.name,
        due_date: c.due_date,
        call_date: c.call_date,
        call_amount: c.call_amount.format,
        collected_amount: c.collected_amount.format,
        due_amount: c.due_amount.format,
        percentage_called: c.percentage_called,
        percentage_raised: c.percentage_raised,
        status: c.status,
        approved: c.approved
      }
    end
  end

  # Lists capital commitments filtered by fund, folio, or other criteria.
  #
  # @param fund_id [Integer, nil] Filter by fund ID.
  # @param folio_id [String, nil] Filter by folio ID.
  # @param scope [String, nil] Predefined scope name.
  # @param query [Hash] Ransack query parameters.
  # @param sort [String, nil] Sort string.
  # @return [Array<Hash>] List of capital commitments.
  def list_capital_commitments(fund_id: nil, folio_id: nil, scope: nil, query: {}, sort: nil)
    ransack_query = query || {}
    ransack_query[:s] ||= sort if sort.present?
    ransack_query[:fund_id_eq] = fund_id if fund_id.present?
    ransack_query[:folio_id_eq] = folio_id if folio_id.present?

    relation = Pundit.policy_scope(@user, CapitalCommitment).includes(:fund)

    # Use HasScope to apply filters safely
    scope_params = scope.present? ? { scope => true } : {}
    relation = CapitalCommitmentQuery.new.perform(collection: relation, params: scope_params)

    commitments = relation.ransack(ransack_query).result
    commitments.map do |c|
      {
        id: c.id,
        folio_id: c.folio_id,
        investor: c.investor_name,
        unit_type: c.unit_type,
        fund_close: c.fund_close,
        committed_amount: c.committed_amount.format,
        call_amount: c.call_amount.format,
        collected_amount: c.collected_amount.format,
        distribution_amount: c.distribution_amount.format,
        commitment_date: c.commitment_date,
        onboarding_completed: c.onboarding_completed
      }
    end
  end

  # Lists capital remittances filtered by fund, folio, or other criteria.
  #
  # @param fund_id [Integer, nil] Filter by fund ID.
  # @param folio_id [String, nil] Filter by folio ID.
  # @param scope [String, nil] Predefined scope name.
  # @param query [Hash] Ransack query parameters.
  # @param sort [String, nil] Sort string.
  # @return [Array<Hash>] List of capital remittances.
  def list_capital_remittances(fund_id: nil, folio_id: nil, scope: nil, query: {}, sort: nil)
    ransack_query = query || {}
    ransack_query[:s] ||= sort if sort.present?
    ransack_query[:fund_id_eq] = fund_id if fund_id.present?
    ransack_query[:folio_id_eq] = folio_id if folio_id.present?

    relation = Pundit.policy_scope(@user, CapitalRemittance).includes(:fund, :capital_call, :capital_commitment)

    # Use HasScope to apply filters safely
    scope_params = scope.present? ? { scope => true } : {}
    relation = CapitalRemittanceQuery.new.perform(collection: relation, params: scope_params)

    remittances = relation.ransack(ransack_query).result
    remittances.map do |r|
      {
        id: r.id,
        investor: r.investor_name,
        folio_id: r.folio_id,
        capital_call: r.capital_call&.name,
        call_amount: r.call_amount.format,
        collected_amount: r.collected_amount.format,
        due_amount: r.due_amount.format,
        status: r.status,
        verified: r.verified,
        fees: {
          capital: r.capital_fee.format,
          other: r.other_fee.format,
          investment: r.investment_amount.format
        }
      }
    end
  end

  # Lists capital distributions for a fund.
  #
  # @param fund_id [Integer] ID of the fund.
  # @param query [Hash] Ransack query parameters.
  # @param sort [String, nil] Sort string.
  # @return [Array<Hash>] List of capital distributions.
  def list_capital_distributions(fund_id:, query: {}, sort: nil)
    ransack_query = query || {}
    ransack_query[:s] ||= sort if sort.present?
    ransack_query[:fund_id_eq] = fund_id

    distributions = Pundit.policy_scope(@user, CapitalDistribution).includes(:fund).ransack(ransack_query).result
    distributions.map do |d|
      {
        id: d.id,
        title: d.title,
        distribution_date: d.distribution_date,
        gross_amount: d.gross_amount.format,
        net_amount: d.distribution_amount.format,
        income: d.income.format,
        reinvestment: d.reinvestment.format,
        notes: d.notes,
        approved: d.approved,
        completed: d.completed
      }
    end
  end

  # Lists payments for capital remittances.
  #
  # @param fund_id [Integer, nil] Filter by fund ID.
  # @param folio_id [String, nil] Filter by folio ID.
  # @param query [Hash] Ransack query parameters.
  # @param sort [String, nil] Sort string.
  # @return [Array<Hash>] List of remittance payments.
  def list_capital_remittance_payments(fund_id: nil, folio_id: nil, query: {}, sort: nil)
    ransack_query = query || {}
    ransack_query[:s] ||= sort if sort.present?
    ransack_query[:fund_id_eq] = fund_id if fund_id.present?
    ransack_query['capital_commitment_folio_id_eq'] = folio_id if folio_id.present?
    payments = Pundit.policy_scope(@user, CapitalRemittancePayment).includes(:fund, :capital_commitment).ransack(ransack_query).result
    payments.map do |p|
      {
        id: p.id,
        fund_name: p.fund.name,
        investor: p.capital_commitment.investor_name,
        folio_id: p.capital_commitment.folio_id,
        amount: p.amount.format,
        payment_date: p.payment_date,
        reference_no: p.reference_no
      }
    end
  end

  # Lists payments for capital distributions.
  #
  # @param fund_id [Integer, nil] Filter by fund ID.
  # @param folio_id [String, nil] Filter by folio ID.
  # @param scope [String, nil] Predefined scope name.
  # @param sort [String, nil] Sort string.
  # @return [Array<Hash>] List of distribution payments.
  def list_capital_distribution_payments(fund_id: nil, folio_id: nil, scope: nil, sort: nil)
    relation = Pundit.policy_scope(@user, CapitalDistributionPayment).includes(:fund, :capital_commitment)
    relation = relation.where(fund_id: fund_id) if fund_id.present?
    relation = relation.joins(:capital_commitment).where(capital_commitments: { folio_id: folio_id }) if folio_id.present?

    # Use HasScope to apply filters safely
    scope_params = scope.present? ? { scope => true } : {}
    relation = CapitalDistributionPaymentQuery.new.perform(collection: relation, params: scope_params)

    payments = sort.present? ? relation.ransack(s: sort).result : relation
    payments.map do |p|
      {
        id: p.id,
        fund_name: p.fund.name,
        investor: p.investor_name,
        folio_id: p.capital_commitment.folio_id,
        net_payable: p.net_payable.format,
        gross_payable: p.gross_payable.format,
        payment_date: p.payment_date,
        units_quantity: p.units_quantity
      }
    end
  end

  # Lists portfolio investments.
  #
  # @param fund_id [Integer, nil] Filter by fund ID.
  # @param scope [String, nil] Predefined scope name.
  # @param query [Hash] Ransack query parameters.
  # @param sort [String, nil] Sort string.
  # @return [Array<Hash>] List of portfolio investments.
  def list_portfolio_investments(fund_id: nil, scope: nil, query: {}, sort: nil)
    ransack_query = query || {}
    ransack_query[:s] ||= sort if sort.present?

    relation = Pundit.policy_scope(@user, PortfolioInvestment).includes(:fund, :portfolio_company, :investment_instrument)
    relation = relation.where(fund_id: fund_id) if fund_id.present?

    # Use HasScope to apply filters safely
    scope_params = scope.present? ? { scope => true } : {}
    relation = PortfolioInvestmentQuery.new.perform(collection: relation, params: scope_params)

    investments = relation.ransack(ransack_query).result
    investments.map do |i|
      {
        id: i.id,
        portfolio_company_name: i.portfolio_company&.name,
        investment_instrument_name: i.investment_instrument&.name,
        investment_date: i.investment_date,
        amount: i.amount.format,
        fmv: i.fmv.format,
        quantity: i.quantity,
        unrealized_gain: i.unrealized_gain.format,
        gain: i.gain.format,
        fund_name: i.fund.name
      }
    end
  end

  # Lists fund ratios.
  #
  # @param fund_id [Integer, nil] Filter by fund ID.
  # @param query [Hash] Ransack query parameters.
  # @param sort [String, nil] Sort string.
  # @return [Array<Hash>] List of fund ratios.
  def list_fund_ratios(fund_id: nil, query: {}, sort: nil)
    ransack_query = query || {}
    ransack_query[:s] ||= sort if sort.present?
    ransack_query[:fund_id_eq] = fund_id if fund_id.present?

    ratios = Pundit.policy_scope(@user, FundRatio).includes(:fund, :portfolio_scenario).ransack(ransack_query).result
    ratios.map do |r|
      {
        id: r.id,
        fund_id: r.fund_id,
        fund_name: r.fund&.name,
        name: r.name,
        value: r.value,
        display_value: r.display_value,
        end_date: r.end_date,
        latest: r.latest,
        owner_type: r.owner_type,
        owner_id: r.owner_id,
        scenario: r.scenario,
        portfolio_scenario: r.portfolio_scenario&.name
      }
    end
  end
end
