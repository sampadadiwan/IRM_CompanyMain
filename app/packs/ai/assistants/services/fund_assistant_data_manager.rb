# FundAssistantDataManager
#
# Handles the business logic and data retrieval for the FundAssistant.
# This class contains the implementation of the actions exposed by the assistant's tools.
# It uses Pundit policies to ensure the user only accesses authorized data and
# Ransack for flexible querying.
#
# rubocop:disable Metrics/CyclomaticComplexity
class FundAssistantDataManager
  attr_accessor :assistant

  # Query object for filtering CapitalRemittances.
  class CapitalRemittanceQuery
    include HasScope

    has_scope :paid, type: :boolean
    has_scope :unpaid, type: :boolean
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

  # Query object for filtering AccountEntries.
  class AccountEntryQuery
    include HasScope

    has_scope :cumulative, type: :boolean
    has_scope :not_cumulative, type: :boolean
    has_scope :generated, type: :boolean
    has_scope :fund_entries, type: :boolean
    has_scope :reporting, type: :boolean
    has_scope :accounting, type: :boolean
    has_scope :for_folios, type: :boolean
    has_scope :for_portfolio_investments, type: :boolean
    has_scope :for_portfolio_companies, type: :boolean

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

  def data_manager
    self
  end

  # Lists funds based on filters.
  #
  # @param scope [String, nil] Predefined scope name (e.g., 'master_funds').
  # @param query [Hash] Ransack query parameters.
  # @param sort [String, nil] Sort string (e.g., 'name asc').
  # @param limit [Integer, nil] Maximum number of records to return.
  # @param aggregate [String, nil] Optional aggregation: 'count'.
  # @return [Array<Hash>, Hash] List of fund data or aggregate result.
  def list_funds(scope: nil, query: {}, sort: nil, limit: nil, aggregate: nil)
    Rails.logger.debug { "[FundAssistantDataManager] list_funds called with scope: #{scope.inspect}, query: #{query.inspect}, sort: #{sort.inspect}, limit: #{limit.inspect}, aggregate: #{aggregate.inspect}" }
    ransack_query = (query || {}).with_indifferent_access
    ransack_query[:s] ||= sort if sort.present?

    relation = Pundit.policy_scope(@user, Fund)

    # Use HasScope to apply filters safely
    scope_params = scope.present? ? { scope.to_sym => true } : {}
    relation = FundQuery.new.perform(collection: relation, params: scope_params)

    results = relation.ransack(ransack_query).result

    return perform_aggregation(results, aggregate, field: query&.dig(:aggregate_field), group_by: query&.dig(:group_by)) if aggregate.present?

    results = results.limit(limit) if limit.present?

    results.map do |f|
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
        call_amount: f.call_amount.format,
        view_link: "/funds/#{f.id}"
      }
    end
  end

  # Retrieves detailed information for a specific fund.
  #
  # @param fund_id [Integer] ID of the fund.
  # @return [Hash, String] Fund details or error message if not found/denied.
  def get_fund_details(fund_id:)
    Rails.logger.debug { "[FundAssistantDataManager] get_fund_details called with fund_id: #{fund_id.inspect}" }
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
      signatory_emails: fund.esign_emails,
      view_link: "/funds/#{fund.id}"
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
  # @param fund_ids [Array<Integer>, Integer, nil] Filter by fund IDs.
  # @param scope [String, nil] Predefined scope name.
  # @param query [Hash] Ransack query parameters.
  # @param sort [String, nil] Sort string.
  # @param limit [Integer, nil] Maximum number of records to return.
  # @param aggregate [String, nil] Optional aggregation: 'count'.
  # @return [Array<Hash>, Hash] List of capital calls or aggregate result.
  def list_capital_calls(fund_ids: nil, scope: nil, query: {}, sort: nil, limit: nil, aggregate: nil)
    Rails.logger.debug { "[FundAssistantDataManager] list_capital_calls called with fund_ids: #{fund_ids.inspect}, scope: #{scope.inspect}, query: #{query.inspect}, sort: #{sort.inspect}, limit: #{limit.inspect}, aggregate: #{aggregate.inspect}" }
    ransack_query = (query || {}).with_indifferent_access
    ransack_query[:s] ||= sort if sort.present?
    ransack_query[:fund_id_in] = Array(fund_ids) if fund_ids.present?

    relation = Pundit.policy_scope(@user, CapitalCall)
    relation = relation.send(scope) if scope.present? && relation.respond_to?(scope)

    results = relation.ransack(ransack_query).result

    return perform_aggregation(results, aggregate, field: query&.dig(:aggregate_field), group_by: query&.dig(:group_by)) if aggregate.present?

    results = results.limit(limit) if limit.present?

    results.map do |c|
      {
        id: c.id,
        name: c.name,
        due_date: c.due_date,
        call_basis: c.call_basis,
        call_date: c.call_date,
        call_amount: c.call_amount.format,
        collected_amount: c.collected_amount.format,
        due_amount: c.due_amount.format,
        percentage_called: c.percentage_called,
        close_percentages: c.close_percentages,
        approved: c.approved,
        view_link: "/capital_calls/#{c.id}"
      }
    end
  end

  # Lists capital commitments filtered by fund, folio, or other criteria.
  #
  # @param fund_ids [Array<Integer>, Integer, nil] Filter by fund IDs.
  # @param folio_ids [Array<String>, String, nil] Filter by folio IDs.
  # @param scope [String, nil] Predefined scope name.
  # @param query [Hash] Ransack query parameters.
  # @param sort [String, nil] Sort string.
  # @param limit [Integer, nil] Maximum number of records to return.
  # @param aggregate [String, nil] Optional aggregation: 'count'.
  # @return [Array<Hash>, Hash] List of capital commitments or aggregate result.
  def list_capital_commitments(fund_ids: nil, folio_ids: nil, scope: nil, query: {}, sort: nil, limit: nil, aggregate: nil)
    Rails.logger.debug { "[FundAssistantDataManager] list_capital_commitments called with fund_ids: #{fund_ids.inspect}, folio_ids: #{folio_ids.inspect}, scope: #{scope.inspect}, query: #{query.inspect}, sort: #{sort.inspect}, limit: #{limit.inspect}, aggregate: #{aggregate.inspect}" }
    ransack_query = (query || {}).with_indifferent_access
    ransack_query[:s] ||= sort if sort.present?
    ransack_query[:fund_id_in] = Array(fund_ids) if fund_ids.present?
    ransack_query[:folio_id_in] = Array(folio_ids) if folio_ids.present?

    relation = Pundit.policy_scope(@user, CapitalCommitment).includes(:fund)

    # Use HasScope to apply filters safely
    scope_params = scope.present? ? { scope.to_sym => true } : {}
    relation = CapitalCommitmentQuery.new.perform(collection: relation, params: scope_params)

    # Join with investor if sorting or grouping by investor attributes
    relation = relation.joins(:investor) if query&.dig(:group_by)&.include?("investor_") || query&.dig(:aggregate_field)&.include?("investor_") || sort&.include?("investor_")

    results = relation.ransack(ransack_query).result

    return perform_aggregation(results, aggregate, field: query&.dig(:aggregate_field), group_by: query&.dig(:group_by)) if aggregate.present?

    results = results.limit(limit) if limit.present?

    results.map do |c|
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
        onboarding_completed: c.onboarding_completed,
        view_link: "/capital_commitments/#{c.id}"
      }
    end
  end

  # Lists capital remittances filtered by fund, folio, or other criteria.
  #
  # @param fund_ids [Array<Integer>, Integer, nil] Filter by fund IDs.
  # @param folio_ids [Array<String>, String, nil] Filter by folio IDs.
  # @param scope [String, nil] Predefined scope name.
  # @param query [Hash] Ransack query parameters.
  # @param sort [String, nil] Sort string.
  # @param limit [Integer, nil] Maximum number of records to return.
  # @param aggregate [String, nil] Optional aggregation: 'count'.
  # @return [Array<Hash>, Hash] List of capital remittances or aggregate result.
  def list_capital_remittances(fund_ids: nil, folio_ids: nil, scope: nil, query: {}, sort: nil, limit: nil, aggregate: nil)
    Rails.logger.debug { "[FundAssistantDataManager] list_capital_remittances called with fund_ids: #{fund_ids.inspect}, folio_ids: #{folio_ids.inspect}, scope: #{scope.inspect}, query: #{query.inspect}, sort: #{sort.inspect}, limit: #{limit.inspect}, aggregate: #{aggregate.inspect}" }
    ransack_query = (query || {}).with_indifferent_access
    ransack_query[:s] ||= sort if sort.present?
    ransack_query[:fund_id_in] = Array(fund_ids) if fund_ids.present?
    ransack_query[:folio_id_in] = Array(folio_ids) if folio_ids.present?

    relation = Pundit.policy_scope(@user, CapitalRemittance).includes(:fund, :capital_call, :capital_commitment)

    # Use HasScope to apply filters safely
    scope_params = scope.present? ? { scope.to_sym => true } : {}
    relation = CapitalRemittanceQuery.new.perform(collection: relation, params: scope_params)

    results = relation.ransack(ransack_query).result

    return perform_aggregation(results, aggregate, field: query&.dig(:aggregate_field), group_by: query&.dig(:group_by)) if aggregate.present?

    results = results.limit(limit) if limit.present?

    results.map do |r|
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
        },
        view_link: "/capital_remittances/#{r.id}"
      }
    end
  end

  # Lists capital distributions for a fund.
  #
  # @param fund_ids [Array<Integer>, Integer, nil] Filter by fund IDs.
  # @param scope [String, nil] Predefined scope name.
  # @param query [Hash] Ransack query parameters.
  # @param sort [String, nil] Sort string.
  # @param limit [Integer, nil] Maximum number of records to return.
  # @param aggregate [String, nil] Optional aggregation: 'count'.
  # @return [Array<Hash>, Hash] List of capital distributions or aggregate result.
  def list_capital_distributions(fund_ids: nil, scope: nil, query: {}, sort: nil, limit: nil, aggregate: nil)
    Rails.logger.debug { "[FundAssistantDataManager] list_capital_distributions called with fund_ids: #{fund_ids.inspect}, scope: #{scope.inspect}, query: #{query.inspect}, sort: #{sort.inspect}, limit: #{limit.inspect}, aggregate: #{aggregate.inspect}" }
    ransack_query = (query || {}).with_indifferent_access
    ransack_query[:s] ||= sort if sort.present?
    ransack_query[:fund_id_in] = Array(fund_ids) if fund_ids.present?

    relation = Pundit.policy_scope(@user, CapitalDistribution).includes(:fund)
    relation = relation.send(scope) if scope.present? && relation.respond_to?(scope)

    results = relation.ransack(ransack_query).result

    return perform_aggregation(results, aggregate, field: query&.dig(:aggregate_field), group_by: query&.dig(:group_by)) if aggregate.present?

    results = results.limit(limit) if limit.present?

    results.map do |d|
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
        completed: d.completed,
        view_link: "/capital_distributions/#{d.id}"
      }
    end
  end

  # Lists payments for capital remittances.
  #
  # @param fund_ids [Array<Integer>, Integer, nil] Filter by fund IDs.
  # @param folio_ids [Array<String>, String, nil] Filter by folio IDs.
  # @param scope [String, nil] Predefined scope name.
  # @param query [Hash] Ransack query parameters.
  # @param sort [String, nil] Sort string.
  # @param limit [Integer, nil] Maximum number of records to return.
  # @param aggregate [String, nil] Optional aggregation: 'count'.
  # @return [Array<Hash>, Hash] List of remittance payments or aggregate result.
  def list_capital_remittance_payments(fund_ids: nil, folio_ids: nil, scope: nil, query: {}, sort: nil, limit: nil, aggregate: nil)
    Rails.logger.debug { "[FundAssistantDataManager] list_capital_remittance_payments called with fund_ids: #{fund_ids.inspect}, folio_ids: #{folio_ids.inspect}, scope: #{scope.inspect}, query: #{query.inspect}, sort: #{sort.inspect}, limit: #{limit.inspect}, aggregate: #{aggregate.inspect}" }
    ransack_query = (query || {}).with_indifferent_access
    ransack_query[:s] ||= sort if sort.present?
    ransack_query[:fund_id_in] = Array(fund_ids) if fund_ids.present?
    ransack_query[:capital_commitment_folio_id_in] = Array(folio_ids) if folio_ids.present?

    relation = Pundit.policy_scope(@user, CapitalRemittancePayment).includes(:fund, :capital_commitment)
    relation = relation.send(scope) if scope.present? && relation.respond_to?(scope)

    results = relation.ransack(ransack_query).result

    return perform_aggregation(results, aggregate, field: query&.dig(:aggregate_field), group_by: query&.dig(:group_by)) if aggregate.present?

    results = results.limit(limit) if limit.present?

    results.map do |p|
      {
        id: p.id,
        fund_name: p.fund.name,
        investor: p.capital_commitment.investor_name,
        folio_id: p.capital_commitment.folio_id,
        amount: p.amount.format,
        payment_date: p.payment_date,
        reference_no: p.reference_no,
        view_link: "/capital_remittance_payments/#{p.id}"
      }
    end
  end

  # Lists payments for capital distributions.
  #
  # @param fund_ids [Array<Integer>, Integer, nil] Filter by fund IDs.
  # @param folio_ids [Array<String>, String, nil] Filter by folio IDs.
  # @param scope [String, nil] Predefined scope name.
  # @param query [Hash] Ransack query parameters.
  # @param sort [String, nil] Sort string.
  # @param limit [Integer, nil] Maximum number of records to return.
  # @param aggregate [String, nil] Optional aggregation: 'count'.
  # @return [Array<Hash>, Hash] List of distribution payments or aggregate result.
  def list_capital_distribution_payments(fund_ids: nil, folio_ids: nil, scope: nil, query: {}, sort: nil, limit: nil, aggregate: nil)
    Rails.logger.debug { "[FundAssistantDataManager] list_capital_distribution_payments called with fund_ids: #{fund_ids.inspect}, folio_ids: #{folio_ids.inspect}, scope: #{scope.inspect}, query: #{query.inspect}, sort: #{sort.inspect}, limit: #{limit.inspect}, aggregate: #{aggregate.inspect}" }
    ransack_query = (query || {}).with_indifferent_access
    ransack_query[:s] ||= sort if sort.present?
    ransack_query[:fund_id_in] = Array(fund_ids) if fund_ids.present?
    ransack_query[:capital_commitment_folio_id_in] = Array(folio_ids) if folio_ids.present?

    relation = Pundit.policy_scope(@user, CapitalDistributionPayment).includes(:fund, :capital_commitment)

    # Use HasScope to apply filters safely
    scope_params = scope.present? ? { scope.to_sym => true } : {}
    relation = CapitalDistributionPaymentQuery.new.perform(collection: relation, params: scope_params)

    results = relation.ransack(ransack_query).result

    return perform_aggregation(results, aggregate, field: query&.dig(:aggregate_field), group_by: query&.dig(:group_by)) if aggregate.present?

    results = results.limit(limit) if limit.present?

    results.map do |p|
      {
        id: p.id,
        fund_name: p.fund.name,
        investor: p.investor_name,
        folio_id: p.capital_commitment.folio_id,
        net_payable: p.net_payable.format,
        gross_payable: p.gross_payable.format,
        payment_date: p.payment_date,
        units_quantity: p.units_quantity,
        view_link: "/capital_distribution_payments/#{p.id}"
      }
    end
  end

  # Lists portfolio investments.
  #
  # @param fund_ids [Array<Integer>, Integer, nil] Filter by fund IDs.
  # @param scope [String, nil] Predefined scope name.
  # @param query [Hash] Ransack query parameters.
  # @param sort [String, nil] Sort string.
  # @param limit [Integer, nil] Maximum number of records to return.
  # @param aggregate [String, nil] Optional aggregation: 'count'.
  # @return [Array<Hash>, Hash] List of portfolio investments or aggregate result.
  def list_portfolio_investments(fund_ids: nil, scope: nil, query: {}, sort: nil, limit: nil, aggregate: nil)
    Rails.logger.debug { "[FundAssistantDataManager] list_portfolio_investments called with fund_ids: #{fund_ids.inspect}, scope: #{scope.inspect}, query: #{query.inspect}, sort: #{sort.inspect}, limit: #{limit.inspect}, aggregate: #{aggregate.inspect}" }
    ransack_query = (query || {}).with_indifferent_access
    ransack_query[:s] ||= sort if sort.present?

    relation = Pundit.policy_scope(@user, PortfolioInvestment).includes(:fund, :portfolio_company, :investment_instrument)
    relation = relation.where(fund_id: fund_ids) if fund_ids.present?

    # Use HasScope to apply filters safely
    scope_params = scope.present? ? { scope.to_sym => true } : {}
    relation = PortfolioInvestmentQuery.new.perform(collection: relation, params: scope_params)

    results = relation.ransack(ransack_query).result

    return perform_aggregation(results, aggregate, field: query&.dig(:aggregate_field), group_by: query&.dig(:group_by)) if aggregate.present?

    results = results.limit(limit) if limit.present?

    results.map do |i|
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
        fund_name: i.fund.name,
        view_link: "/portfolio_investments/#{i.id}"
      }
    end
  end

  # Lists fund ratios.
  #
  # @param fund_ids [Array<Integer>, Integer, nil] Filter by fund IDs.
  # @param scope [String, nil] Predefined scope name.
  # @param query [Hash] Ransack query parameters.
  # @param sort [String, nil] Sort string.
  # @param limit [Integer, nil] Maximum number of records to return.
  # @param aggregate [String, nil] Optional aggregation: 'count'.
  # @return [Array<Hash>, Hash] List of fund ratios or aggregate result.
  def list_fund_ratios(fund_ids: nil, scope: nil, query: {}, sort: nil, limit: nil, owner: nil, aggregate: nil)
    Rails.logger.debug { "[FundAssistantDataManager] list_fund_ratios called with fund_ids: #{fund_ids.inspect}, scope: #{scope.inspect}, query: #{query.inspect}, sort: #{sort.inspect}, limit: #{limit.inspect}, aggregate: #{aggregate.inspect}" }
    ransack_query = (query || {}).with_indifferent_access
    ransack_query[:s] ||= sort if sort.present?
    ransack_query[:fund_id_in] = Array(fund_ids) if fund_ids.present?

    relation = Pundit.policy_scope(@user, FundRatio).preload(:fund, :computation_context)
    if owner.present?
      ransack_query[:owner_type_eq] = owner[:type]
      ransack_query[:owner_id_eq] = owner[:id]
    else
      ransack_query[:owner_type_eq] = 'Fund'
      ransack_query[:owner_id_eq] = fund_ids if fund_ids.present?
    end
    relation = relation.send(scope) if scope.present? && relation.respond_to?(scope)

    results = relation.ransack(ransack_query).result

    return perform_aggregation(results, aggregate, field: query&.dig(:aggregate_field), group_by: query&.dig(:group_by)) if aggregate.present?

    results = results.limit(limit) if limit.present?

    results.map do |r|
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
        portfolio_scenario: r.computation_context&.name,
        view_link: "/fund_ratios/#{r.id}"
      }
    end
  end

  # Lists account entries based on filters.
  #
  # @param fund_ids [Array<Integer>, Integer, nil] Filter by fund IDs.
  # @param folio_ids [Array<String>, String, nil] Filter by folio IDs.
  # @param scope [String, nil] Predefined scope name.
  # @param query [Hash] Ransack query parameters.
  # @param sort [String, nil] Sort string.
  # @param limit [Integer, nil] Maximum number of records to return.
  # @param aggregate [String, nil] Optional aggregation: 'count', 'sum', 'group_by'.
  # @return [Hash] List of account entry data or aggregate result.
  def list_account_entries(fund_ids: nil, folio_ids: nil, scope: nil, query: {}, sort: nil, limit: nil, aggregate: nil)
    Rails.logger.debug { "[FundAssistantDataManager] list_account_entries called with fund_ids: #{fund_ids.inspect}, folio_ids: #{folio_ids.inspect}, scope: #{scope.inspect}, query: #{query.inspect}, sort: #{sort.inspect}, limit: #{limit.inspect}, aggregate: #{aggregate.inspect}" }

    raise "Aggregation is MANDATORY for list_account_entries. Individual records cannot be fetched." if aggregate.blank?

    ransack_query = (query || {}).with_indifferent_access
    ransack_query[:s] ||= sort if sort.present?
    ransack_query[:fund_id_in] = Array(fund_ids) if fund_ids.present?
    ransack_query[:folio_id_in] = Array(folio_ids) if folio_ids.present?

    relation = Pundit.policy_scope(@user, AccountEntry).includes(:fund)

    # Use HasScope to apply filters safely
    scope_params = scope.present? ? { scope.to_sym => true } : {}
    relation = AccountEntryQuery.new.perform(collection: relation, params: scope_params)

    results = relation.ransack(ransack_query).result

    perform_aggregation(results, aggregate, field: ransack_query[:aggregate_field] || 'amount', group_by: ransack_query[:group_by])
  end

  private

  # Performs aggregation on a relation using database queries.
  # This method ensures that aggregations (count, sum, group_by) are performed
  # at the database level rather than loading all records into memory.
  #
  # @param results [ActiveRecord::Relation] The relation to aggregate.
  # @param aggregate [String] Aggregation type ('count', 'sum', 'group_by').
  # @param field [String, nil] The field to aggregate on.
  # @param group_by [String, nil] The field to group by.
  # @return [Hash] Aggregation result.
  def perform_aggregation(results, aggregate, field: nil, group_by: nil)
    Rails.logger.debug { "[FundAssistantDataManager] perform_aggregation: aggregate=#{aggregate}, field=#{field}, group_by=#{group_by}" }

    case aggregate
    when 'count'
      # Direct database count query: SELECT COUNT(*) FROM ...
      { count: results.count }
    when 'sum'
      return { error: "Field is required for sum aggregation" } if field.blank?

      sum_field = field.to_s
      # If it's a Money column, we aggregate the _cents column directly in the DB
      sum_field = "#{sum_field}_cents" if results.model.column_names.include?("#{sum_field}_cents")

      # Execute database sum query: SELECT SUM(field) FROM ...
      total = results.sum(sum_field)
      { total: total }
    when 'group_by'
      return { error: "Group by field is required" } if group_by.blank?
      return { error: "Field is required for group_by aggregation (e.g., sum or count of field)" } if field.blank?

      group_field = group_by.to_s
      sum_field = field.to_s

      # Handle mapping for joined tables (e.g., investor details)
      group_field = 'investors.category' if group_field == 'investor_category' && results.model.column_names.exclude?('investor_category')

      # Unscope order to avoid SQL grouping errors
      base_relation = results.unscope(:order).group(group_field)

      if sum_field == 'id'
        # Grouped count query: SELECT group_field, COUNT(id) ... GROUP BY group_field
        grouped_data = base_relation.count
        formatted_data = grouped_data.map do |key, value|
          { group: key, count: value }
        end
      else
        # Grouped sum query: SELECT group_field, SUM(sum_field) ... GROUP BY group_field
        sum_field = "#{sum_field}_cents" if results.model.column_names.include?("#{sum_field}_cents")
        grouped_data = base_relation.sum(sum_field)

        formatted_data = grouped_data.map do |key, value|
          { group: key, total: value }
        end
      end

      { groups: formatted_data }
    else
      { error: "Unsupported aggregation type: #{aggregate}" }
    end
  end
end
# rubocop:enable Metrics/CyclomaticComplexity
