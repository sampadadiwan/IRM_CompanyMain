# PortfolioAssistantDataManager
#
# Handles business logic and data retrieval for the PortfolioAssistant.
# Focused on portfolio company specific data: valuations, investments, KPIs, and documents.
#
class PortfolioAssistantDataManager
  include WithFilterParams

  # Query object for filtering Investors/portfolio companies. HasScope only ever invokes
  # scopes declared here, so an LLM-supplied `scope` string can never reach an arbitrary
  # method (e.g. `destroy_all`) the way a raw `relation.send(scope)` could.
  class InvestorQuery
    include HasScope

    has_scope :portfolio_companies, type: :boolean
    has_scope :not_portfolio_companies, type: :boolean
    has_scope :advisors, type: :boolean
    has_scope :rms, type: :boolean
    has_scope :without_investor_accesses, type: :boolean

    def perform(collection:, params:)
      apply_scopes(collection, params)
    end
  end

  # Query object for filtering Valuations.
  class ValuationQuery
    include HasScope

    has_scope :with_synthetic, type: :boolean

    def perform(collection:, params:)
      apply_scopes(collection, params)
    end
  end

  # Query object for filtering Documents.
  class DocumentQuery
    include HasScope

    has_scope :approved, type: :boolean
    has_scope :not_approved, type: :boolean
    has_scope :template, type: :boolean
    has_scope :not_template, type: :boolean
    has_scope :sent_for_esign, type: :boolean
    has_scope :not_sent_for_esign, type: :boolean
    has_scope :signed, type: :boolean
    has_scope :esign_status_completed, type: :boolean
    has_scope :esign_status_failed, type: :boolean
    has_scope :esign_status_requested, type: :boolean

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

  # Query object for filtering KPIs.
  class KpiQuery
    include HasScope

    has_scope :actuals, type: :boolean
    has_scope :budgets, type: :boolean
    has_scope :ics, type: :boolean
    has_scope :monthly, type: :boolean
    has_scope :quarterly, type: :boolean
    has_scope :yearly, type: :boolean
    has_scope :ytd, type: :boolean

    def perform(collection:, params:)
      Rails.logger.debug { "[KpiQuery] perform called with collection class: #{collection.klass.name}, params: #{params.inspect}" }
      result = apply_scopes(collection, params)
      Rails.logger.debug { "[KpiQuery] perform returning collection with SQL: #{result.to_sql}" }
      result
    end
  end

  # Server-side ceiling applied whenever a caller (the LLM) doesn't supply an explicit
  # `limit`. Prompt instructions alone ("ALWAYS pass limit") are not a reliable guardrail --
  # this backstops it in code so an unfiltered/unlimited-looking request can't pull an
  # unbounded result set into the LLM's context.
  DEFAULT_QUERY_LIMIT = 500

  def initialize(user:)
    @user = user
  end

  # Applies the caller's limit if given, otherwise falls back to DEFAULT_QUERY_LIMIT.
  def bounded_limit(relation, limit)
    relation.limit(limit.presence || DEFAULT_QUERY_LIMIT)
  end
  private :bounded_limit

  # Returns an error hash when `scope` was supplied but isn't declared on `query_class` (a
  # HasScope-including *Query class). Before this, an unrecognized/hallucinated scope name
  # was silently dropped -- the LLM's tool call looked successful but quietly returned an
  # *unfiltered* result, with no signal that the requested scope didn't exist. Returns nil
  # when scope is blank or recognized, so callers can `return error if error`. Not used by
  # list_portfolio_kpis, which has its own deliberate compound-scope fallback behavior.
  def unrecognized_scope_error(query_class, scope)
    return nil if scope.blank? || query_class.scopes_configuration.key?(scope.to_sym)

    { error: "Unknown scope '#{scope}'. Valid scopes: #{query_class.scopes_configuration.keys.join(', ')}" }
  end
  private :unrecognized_scope_error

  # Resolves a single portfolio_company_id (when given) to a 1-element id array, or --
  # when nil -- to every portfolio company id the user is allowed to see. Centralizes the
  # "optional company scope" fallback shared by list_valuations/list_portfolio_investments/
  # list_documents so a chart/report request that spans the whole portfolio doesn't need a
  # company pre-resolved first.
  def resolve_owner_ids(portfolio_company_id)
    scope = Pundit.policy_scope(@user, Investor).portfolio_companies
    if portfolio_company_id.present?
      scope.where(id: portfolio_company_id).pluck(:id)
    else
      scope.pluck(:id)
    end
  end
  private :resolve_owner_ids

  # Lists portfolio companies (Investors with category 'Portfolio Company').
  def list_portfolio_companies(scope: nil, query: {}, sort: nil, limit: nil, aggregate: nil)
    Rails.logger.debug { "[PortfolioAssistantDataManager] list_portfolio_companies called with scope: #{scope.inspect}, query: #{query.inspect}, sort: #{sort.inspect}, limit: #{limit.inspect}, aggregate: #{aggregate.inspect}" }
    ransack_query = query || {}
    ransack_query[:s] ||= sort if sort.present?

    relation = Pundit.policy_scope(@user, Investor).portfolio_companies

    # Route scope through a declared allowlist (HasScope), never a raw `send` -- Investor
    # (like every AR model) responds_to? real methods such as destroy_all/delete_all/
    # update_all, so `relation.send(scope) if relation.respond_to?(scope)` would let an
    # LLM-supplied scope string execute one of those against every row this user can see.
    scope_error = unrecognized_scope_error(InvestorQuery, scope)
    return scope_error if scope_error

    scope_params = scope.present? ? { scope.to_sym => true } : {}
    relation = InvestorQuery.new.perform(collection: relation, params: scope_params)
    results = relation.ransack(ransack_query).result

    return FundAssistantDataManager.new(user: @user).send(:perform_aggregation, results, aggregate, field: query&.dig(:aggregate_field), group_by: query&.dig(:group_by)) if aggregate.present?

    results = bounded_limit(results, limit)

    results.map do |c|
      {
        id: c.id,
        name: c.investor_name,
        category: c.category,
        city: c.city,
        tags: c.tag_list,
        view_link: "/investors/#{c.id}"
      }
    end
  end

  # Gets basic details for a specific portfolio company.
  def get_portfolio_company_details(portfolio_company_id:)
    Rails.logger.debug { "[PortfolioAssistantDataManager] get_portfolio_company_details called with portfolio_company_id: #{portfolio_company_id.inspect}" }
    company = Pundit.policy_scope(@user, Investor).portfolio_companies.find_by(id: portfolio_company_id)
    return "Portfolio Company not found or access denied" unless company

    {
      id: company.id,
      name: company.investor_name,
      category: company.category,
      primary_email: company.primary_email,
      tags: company.tag_list.to_s,
      city: company.city,
      amount_invested: company.amount_invested.format,
      last_interaction: (I18n.l(company.last_interaction_date) if company.last_interaction_date.present?),
      view_link: "/investors/#{company.id}"
    }
  end

  # Lists valuations for a portfolio company. When portfolio_company_id is omitted, lists
  # across every portfolio company the user can see instead -- this is what lets
  # plot_chart_from_query(resource: "valuations") work without pre-resolving a single
  # company; previously portfolio_company_id was a mandatory keyword here, which raised
  # ArgumentError whenever that tool's generic fetch path called this without one.
  def list_valuations(portfolio_company_id: nil, scope: nil, query: {}, sort: nil, limit: nil, aggregate: nil)
    Rails.logger.debug { "[PortfolioAssistantDataManager] list_valuations called with portfolio_company_id: #{portfolio_company_id.inspect}, scope: #{scope.inspect}, query: #{query.inspect}, sort: #{sort.inspect}, limit: #{limit.inspect}, aggregate: #{aggregate.inspect}" }
    owner_ids = resolve_owner_ids(portfolio_company_id)
    return [] if owner_ids.empty?

    ransack_query = query || {}
    ransack_query[:s] ||= sort if sort.present?

    relation = Pundit.policy_scope(@user, Valuation).includes(:portfolio_company, :entity, :investment_instrument).where(owner_type: 'Investor', owner_id: owner_ids)

    # See list_portfolio_companies above for why this must be a declared allowlist, not a raw send.
    scope_error = unrecognized_scope_error(ValuationQuery, scope)
    return scope_error if scope_error

    scope_params = scope.present? ? { scope.to_sym => true } : {}
    relation = ValuationQuery.new.perform(collection: relation, params: scope_params)
    results = relation.ransack(ransack_query).result

    return FundAssistantDataManager.new(user: @user).send(:perform_aggregation, results, aggregate, field: query&.dig(:aggregate_field), group_by: query&.dig(:group_by)) if aggregate.present?

    results = bounded_limit(results, limit)

    results.map do |v|
      {
        id: v.id,
        entity: v.entity.name,
        owner: v.portfolio_company&.investor_name,
        instrument: v.investment_instrument&.name,
        valuation_date: (I18n.l(v.valuation_date) if v.valuation_date),
        per_share_value: (v.per_share_value_cents / 100.0),
        currency: v.currency,
        synthetic: v.synthetic,
        view_link: "/valuations/#{v.id}"
      }
    end
  end

  # Lists portfolio investments for a portfolio company. As with list_valuations,
  # portfolio_company_id is optional and falls back to every portfolio company the user
  # can see -- required for plot_chart_from_query(resource: "portfolio_investments"),
  # which the system prompt explicitly directs the model to use for cross-portfolio charts.
  def list_portfolio_investments(portfolio_company_id: nil, scope: nil, query: {}, sort: nil, limit: nil, aggregate: nil)
    Rails.logger.debug { "[PortfolioAssistantDataManager] list_portfolio_investments called with portfolio_company_id: #{portfolio_company_id.inspect}, scope: #{scope.inspect}, query: #{query.inspect}, sort: #{sort.inspect}, limit: #{limit.inspect}, aggregate: #{aggregate.inspect}" }
    owner_ids = resolve_owner_ids(portfolio_company_id)
    return [] if owner_ids.empty?

    ransack_query = query || {}
    ransack_query[:s] ||= sort if sort.present?

    relation = Pundit.policy_scope(@user, PortfolioInvestment).includes(:fund, :portfolio_company, :investment_instrument).where(portfolio_company_id: owner_ids)

    # See list_portfolio_companies above for why this must be a declared allowlist, not a raw
    # send. PortfolioInvestmentQuery already existed above but was unused here -- this call
    # site was the vulnerable one.
    scope_error = unrecognized_scope_error(PortfolioInvestmentQuery, scope)
    return scope_error if scope_error

    scope_params = scope.present? ? { scope.to_sym => true } : {}
    relation = PortfolioInvestmentQuery.new.perform(collection: relation, params: scope_params)

    results = relation.ransack(ransack_query).result

    return FundAssistantDataManager.new(user: @user).send(:perform_aggregation, results, aggregate, field: query&.dig(:aggregate_field), group_by: query&.dig(:group_by)) if aggregate.present?

    results = bounded_limit(results, limit)

    results.map do |i|
      {
        id: i.id,
        fund: i.fund&.name,
        portfolio_company: i.portfolio_company&.investor_name,
        instrument: i.investment_instrument&.name,
        investment_date: (I18n.l(i.investment_date) if i.investment_date),
        conversion_date: (I18n.l(i.conversion_date) if i.conversion_date),
        instrument_currency: i.investment_instrument&.currency.to_s,
        amount: i.amount.format,
        ex_expenses_amount: i.ex_expenses_amount.format,
        net_amount: i.net_amount.format,
        quantity: i.quantity,
        valuation: i.valuation&.to_s,
        sold_quantity: (i.sold_quantity if i.buy?),
        transfer_quantity: (i.transfer_quantity if i.buy?),
        transfer_amount: (i.transfer_amount.format if i.buy?),
        net_quantity: (i.net_quantity if i.buy?),
        cost_of_remaining: (i.cost_of_remaining if i.buy?),
        cost_per_share: (i.cost.format if i.buy?),
        fmv: i.fmv.format,
        sale_price_per_share: (i.sale_price_per_share.format if i.sell?),
        cost_of_sold: (i.cost_of_sold.format if i.sell?),
        cost_of_sold_per_share: (i.cost_of_sold_per_share.format if i.sell?),
        gain: (i.gain.format if i.sell?),
        unrealized_gain: (i.unrealized_gain.format unless i.sell?),
        startup: i.startup,
        proforma: i.proforma,
        view_link: "/portfolio_investments/#{i.id}"
      }
    end
  end

  # Lists KPIs for portfolio companies.
  def list_portfolio_kpis(portfolio_company_ids: nil, scope: nil, query: {}, sort: nil, limit: nil, aggregate: nil)
    Rails.logger.debug { "[PortfolioAssistantDataManager] list_portfolio_kpis called with portfolio_company_ids: #{portfolio_company_ids.inspect}, scope: #{scope.inspect}, query: #{query.inspect}, sort: #{sort.inspect}, limit: #{limit.inspect}, aggregate: #{aggregate.inspect}" }
    # When portfolio_company_ids is provided, scope KPIs to those specific companies.
    # When nil (e.g. LLM calls with only scope/query filters), fall back to all portfolio
    # companies the user has access to — prevents a silent [] return from WHERE id IS NULL.
    # NOTE: portfolio_company_ids was previously required, causing two problems:
    #   1. The LLM could call this with only scope/query filters (no company IDs) — Ruby raised
    #      ArgumentError before even reaching the guard clause in the tool layer.
    #   2. Even after making it optional in the tool layer, passing nil here produced
    #      WHERE id IS NULL in SQL, returning 0 companies and silently returning [] regardless
    #      of what scope or query filters were provided.
    companies = Pundit.policy_scope(@user, Investor).portfolio_companies
    companies = companies.where(id: portfolio_company_ids) if portfolio_company_ids.present?
    return [] if companies.empty?

    ransack_query = (query || {}).with_indifferent_access
    ransack_query[:s] ||= sort if sort.present?

    # Default kpi_report_as_of to 12 months ago if not provided, but allow user to override
    ransack_query[:kpi_report_as_of_gteq] ||= 12.months.ago.to_date unless ransack_has_attr?(ransack_query, :kpi_report_as_of) || ransack_query[:all_time_eq] == 'true'

    # unless ransack_has_attr?(ransack_query, :period) ||
    #   # Add monthly to the scope
    #   scope += ",monthly"
    # end

    # If scope does not have actuals or budget then add actuals
    scope ||= ""
    scope += ",actuals" unless scope.include?("actuals") || scope.include?("budget")

    Rails.logger.debug { "[KpiQuery Debug] Incoming scope: #{scope.inspect}" }

    # Helper lambda to build and execute the query
    execute_query = lambda do |current_scope|
      relation = Kpi.where(portfolio_company_id: companies.pluck(:id)).includes(:portfolio_company)

      if current_scope.present?
        # If scope is a comma-separated string, convert to hash for KpiQuery
        scope_params = if current_scope.is_a?(String)
                         current_scope.split(',').to_h { |s| [s.strip.to_sym, "true"] }
                       elsif current_scope.is_a?(Symbol)
                         { current_scope => "true" }
                       else
                         current_scope # Assume it's already a hash or compatible
                       end

        Rails.logger.debug { "[KpiQuery Debug] Applying scopes with params: #{scope_params.inspect}" }
        relation = KpiQuery.new.perform(collection: relation, params: scope_params)
      end
      relation.joins(:kpi_report).includes(:kpi_report).ransack(ransack_query).result
    end

    # 1. Determine initial scope to use
    scope_to_use = scope || "monthly,actuals"
    results = execute_query.call(scope_to_use)

    # 2. Smart Fallback Logic
    # If no results found, scope was NOT explicitly provided by user (it was defaulted),
    # then try falling back to a broader search (no scope).
    if results.empty? && scope.nil?
      Rails.logger.info "[PortfolioAssistant] No results found with default 'monthly,actuals' scope. Falling back to unfiltered search."
      results = execute_query.call(nil)
    end

    return FundAssistantDataManager.new(user: @user).send(:perform_aggregation, results, aggregate, field: query&.dig(:aggregate_field), group_by: query&.dig(:group_by)) if aggregate.present?

    results = bounded_limit(results, limit)

    Rails.logger.debug { "[KpiQuery Debug] SQL after ransack: #{results.to_sql}" }
    results.map do |k|
      {
        id: k.id,
        portfolio_company: k.portfolio_company&.investor_name,
        as_of: (I18n.l(k.kpi_report.as_of) if k.kpi_report&.as_of),
        name: k.name,
        period: k.kpi_report&.period,
        value: k.value,
        # display_value: k.display_value,
        # Guard against a bare "%" cell when there's no prior period to compare against.
        percentage_change: (k.percentage_change.nil? ? nil : "#{k.percentage_change}%"),
        # notes: k.notes,
        # source: k.source,
        tag_list: k.kpi_report&.tag_list,
        view_link: "/kpis/#{k.id}"
      }
    end
  end

  # Lists fund ratios.
  #
  # @param portfolio_company_id [Integer, nil] Filter by portfolio company ID.
  # @param query [Hash] Ransack query parameters.
  # @param sort [String, nil] Sort string.
  # @param limit [Integer, nil] Maximum number of records to return.
  # @param aggregate [String, nil] Type of aggregation to perform.
  # @param scope [String, nil] Optional scope name to filter fund ratios (e.g., "latest").
  # @return [Array<Hash>] List of fund ratios.
  def list_fund_ratios(portfolio_company_id: nil, scope: nil, query: {}, sort: nil, limit: nil, aggregate: nil)
    Rails.logger.debug { "[PortfolioAssistantDataManager] list_fund_ratios called with portfolio_company_id: #{portfolio_company_id.inspect}, scope: #{scope.inspect}, query: #{query.inspect}, sort: #{sort.inspect}, limit: #{limit.inspect}, aggregate: #{aggregate.inspect}" }
    ransack_query = query || {}
    ransack_query[:s] ||= sort if sort.present?
    ransack_query[:owner_id_eq] = portfolio_company_id if portfolio_company_id.present?
    ransack_query[:owner_type_eq] = 'Investor' if portfolio_company_id.present?

    relation = Pundit.policy_scope(@user, FundRatio).preload(:fund, :computation_context)
    results = relation.ransack(ransack_query).result

    return FundAssistantDataManager.new(user: @user).send(:perform_aggregation, results, aggregate, field: query&.dig(:aggregate_field), group_by: query&.dig(:group_by)) if aggregate.present?

    results = bounded_limit(results, limit)

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

  # Lists documents associated with the portfolio company. portfolio_company_id is
  # optional, same fallback as list_valuations -- lets plot_chart_from_query(resource:
  # "documents") work across the whole portfolio instead of raising ArgumentError.
  def list_documents(portfolio_company_id: nil, scope: nil, query: {}, sort: nil, limit: nil)
    Rails.logger.debug { "[PortfolioAssistantDataManager] list_documents called with portfolio_company_id: #{portfolio_company_id.inspect}, scope: #{scope.inspect}, query: #{query.inspect}, sort: #{sort.inspect}, limit: #{limit.inspect}" }
    owner_ids = resolve_owner_ids(portfolio_company_id)
    return [] if owner_ids.empty?

    ransack_query = query || {}
    ransack_query[:s] ||= sort if sort.present?

    # Documents are often associated through WithFolder or specific polymorphic associations
    # Assuming documents can be found via the company's entity or specific document relation.
    # kpi_report_ids stays a SQL subquery (not a loaded array of records) so this scales the
    # same way for one company as for the whole portfolio.
    kpi_report_ids = KpiReport.where(portfolio_company_id: owner_ids).select(:id)
    # .includes(:folder) avoids an N+1 -- the map below calls `d.folder&.full_path` per row.
    relation = Pundit.policy_scope(@user, Document).where(owner_type: 'Investor', owner_id: owner_ids).or(
      Pundit.policy_scope(@user, Document).where(owner_type: 'KpiReport', owner_id: kpi_report_ids)
    ).includes(:folder)
    # See list_portfolio_companies above for why this must be a declared allowlist, not a raw send.
    scope_error = unrecognized_scope_error(DocumentQuery, scope)
    return scope_error if scope_error

    scope_params = scope.present? ? { scope.to_sym => true } : {}
    relation = DocumentQuery.new.perform(collection: relation, params: scope_params)
    documents = relation.ransack(ransack_query).result
    documents = bounded_limit(documents, limit)

    documents.map do |d|
      {
        id: d.id,
        name: d.name,
        folder: d.folder&.full_path,
        tags: d.tag_list,
        owner_tag: d.owner_tag,
        created_at: (I18n.l(d.created_at) if d.created_at),
        belongs_to: d.owner_type,
        details: d.text,
        esign_status: d.esign_status&.titleize,
        esign_on_page: d.display_on_page&.titleize,
        esign_order_forced: d.force_esign_order,
        download_file_url: d.file.url,
        view_link: "/documents/#{d.id}"
      }
    end
  end

  # Gets details and text for a specific document.
  def get_document(document_id: nil, name: nil)
    Rails.logger.debug { "[PortfolioAssistantDataManager] get_document called with document_id: #{document_id.inspect}, name: #{name.inspect}" }
    scope = Pundit.policy_scope(@user, Document)
    document = if document_id.present?
                 scope.find_by(id: document_id)
               elsif name.present?
                 # Try exact match first, then partial match
                 scope.find_by(name: name) || scope.where("name LIKE ?", "%#{name}%").first
               end

    return "Document not found or access denied" unless document

    {
      id: document.id,
      name: document.name,
      folder: document.folder&.full_path,
      tags: document.tag_list,
      owner_tag: document.owner_tag,
      created_at: (I18n.l(document.created_at) if document.created_at),
      belongs_to: document.owner_type,
      owner_name: (document.owner.respond_to?(:name) ? document.owner.name : document.owner&.to_s),
      file_url: document.file.url,
      view_link: "/documents/#{document.id}"
    }
  end

  # Analyzes documents using RubyLLM and their file_urls.
  def analyze_documents(prompt:, document_ids: [], document_names: [])
    Rails.logger.debug { "[PortfolioAssistantDataManager] analyze_documents called with prompt: #{prompt.inspect}, document_ids: #{document_ids.inspect}, document_names: #{document_names.inspect}" }
    scope = Pundit.policy_scope(@user, Document)
    documents = []

    documents += scope.where(id: document_ids).to_a if document_ids.present?

    if document_names.present?
      document_names.each do |name|
        doc = scope.find_by(name: name) || scope.where("name LIKE ?", "%#{name}%").first
        documents << doc if doc
      end
    end

    documents.uniq!

    return "No documents found to analyze." if documents.empty?

    # Prepare file URLs for RubyLLM
    attachments = documents.group_by { |d| d.extension.to_sym }.transform_values { |docs| docs.map { |d| d.file.url } }

    chat = LlmService.ruby_llm_chat(entity: @user.entity)
    response = chat.ask prompt, with: attachments
    response.content
  end

  # Generates a cap table for a portfolio company.
  #
  # @param portfolio_company_id [Integer] The ID of the portfolio company.
  # @param funding_rounds [Array<String>, nil] Optional funding rounds to filter by.
  # @param group_by_field [String, Symbol] Field to group the cap table by.
  # @return [Array<Hash>] The cap table data.
  def get_cap_table(portfolio_company_id:, funding_rounds: nil, group_by_field: :investor_name)
    Rails.logger.debug { "[PortfolioAssistantDataManager] get_cap_table called with portfolio_company_id: #{portfolio_company_id.inspect}, funding_rounds: #{funding_rounds.inspect}, group_by_field: #{group_by_field.inspect}" }
    company = Pundit.policy_scope(@user, Investor).portfolio_companies.find_by(id: portfolio_company_id)
    return "Portfolio Company not found or access denied" unless company

    # If funding_rounds not provided, we might want to get all funding rounds for that company
    rounds = funding_rounds
    rounds = Investment.where(portfolio_company_id: company.id).pluck(:funding_round).uniq if rounds.blank?

    return [] if rounds.blank?

    result = GenerateCapTable.call(params: {
                                     funding_rounds: rounds,
                                     portfolio_company_id: company.id,
                                     group_by_field: group_by_field.to_sym
                                   })

    result[:model]
  end

  # Gets investments in cap table across portfolio companies.
  #
  # @param portfolio_company_ids [Array<Integer>] List of portfolio company IDs.
  # @param query [Hash] Optional Ransack query hash.
  # @param sort [String] Optional sort string.
  # @param limit [Integer, nil] Maximum number of records to return.
  # @return [Array<Hash>] List of investments.
  def get_investments_in_cap_table(portfolio_company_ids:, query: {}, sort: nil, limit: nil)
    Rails.logger.debug { "[PortfolioAssistantDataManager] get_investments_in_cap_table called with portfolio_company_ids: #{portfolio_company_ids.inspect}, query: #{query.inspect}, sort: #{sort.inspect}, limit: #{limit.inspect}" }
    companies = Pundit.policy_scope(@user, Investor).portfolio_companies.where(id: portfolio_company_ids)
    return [] if companies.empty?

    ransack_query = query || {}
    ransack_query[:s] ||= sort if sort.present?

    investments = Investment.where(portfolio_company_id: companies.pluck(:id)).ransack(ransack_query).result
    investments = bounded_limit(investments, limit)

    investments.map do |i|
      {
        id: i.id,
        portfolio_company: i.portfolio_company&.investor_name,
        category: i.category,
        investor_name: i.investor_name,
        investment_type: i.investment_type,
        funding_round: i.funding_round,
        currency: i.currency,
        price: i.price.format,
        investment_date: (I18n.l(i.investment_date) if i.investment_date),
        amount: i.amount.format,
        quantity: i.quantity,
        view_link: "/investments/#{i.id}"
      }
    end
  end

  # Gets a high-level snapshot for a specific portfolio company.
  def get_portfolio_company_snapshot(portfolio_company_id:)
    company = Pundit.policy_scope(@user, Investor).portfolio_companies.find_by(id: portfolio_company_id)
    return "Portfolio Company not found or access denied" unless company

    latest_valuation = list_valuations(portfolio_company_id: portfolio_company_id, sort: 'valuation_date desc', limit: 1).first
    tvpi = list_fund_ratios(portfolio_company_id: portfolio_company_id, query: { name_eq: 'TVPI', latest_eq: true }, limit: 1).first
    rvpi = list_fund_ratios(portfolio_company_id: portfolio_company_id, query: { name_eq: 'RVPI', latest_eq: true }, limit: 1).first

    # Group by currency before summing -- a flat `sum(:fmv_cents)` across all of a company's
    # investments silently mixes currencies (adding USD cents to EUR cents) whenever a cap
    # table has instruments in more than one currency, then mislabels the wrong total with
    # whichever currency the *first* investment happened to have. Multi-currency cap tables
    # are reported as a "+"-joined breakdown instead of one misleading number.
    fmv_by_currency = company.portfolio_investments.joins(:investment_instrument).group('investment_instruments.currency').sum(:fmv_cents)
    current_fmv = if fmv_by_currency.size <= 1
                    Money.new(fmv_by_currency.values.first || 0, fmv_by_currency.keys.first || 'USD').format
                  else
                    fmv_by_currency.map { |currency, cents| Money.new(cents, currency).format }.join(' + ')
                  end

    {
      id: company.id,
      name: company.investor_name,
      total_invested: company.amount_invested.format,
      current_fmv: current_fmv,
      latest_valuation: latest_valuation&.slice(:valuation_date, :per_share_value, :currency),
      multiples: {
        tvpi: tvpi&.dig(:display_value) || tvpi&.dig(:value),
        rvpi: rvpi&.dig(:display_value) || rvpi&.dig(:value)
      },
      view_link: "/investors/#{company.id}"
    }
  end
end
