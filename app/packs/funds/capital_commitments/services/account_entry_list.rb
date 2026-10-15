# Service for listing and filtering Account Entries.
#
# This service encapsulates the logic for Ransack search, Pundit scoping,
# custom filters, time series generation, and pivot tables used in the
# AccountEntriesController index action.
#
# It ensures that a policy scope is always applied to the query:
# 1. If a block is given, it yields the relation to the block (allowing controllers to use `policy_scope` helper).
# 2. If no block is given, it uses `Pundit.policy_scope!` directly.
class AccountEntryList < BaseList
  Result = Struct.new(:q, :account_entries, :fund, :fund_defaulted, :data_frame, :adhoc_json, :template, :time_series, :pivot, :row_limit_exceeded, :error, :redirect_url, keyword_init: true)

  # A request narrowed by one of these already returns a small slice of the ledger, whichever
  # fund it is in, so it is not given a default fund (e.g. an import's entries, one folio).
  NARROWING_ATTRIBUTES = %w[capital_commitment_id investor_id import_upload_id folio_id parent_id].freeze

  REPORTING_DATE_LOWER_BOUND_PREDICATES = %w[gt gteq].freeze
  REPORTING_DATE_UPPER_BOUND_PREDICATES = %w[lt lteq].freeze

  # @param current_user [User] The user performing the action.
  # @param params [Hash] The parameters for filtering and search.
  # @param request_referer [String] Optional referer URL for redirects on error.
  # @yield [relation] Optional block for applying policy scope.
  def self.call(current_user, params, request_referer = nil, &)
    new(current_user, params, request_referer).call(&)
  end

  def initialize(current_user, params, request_referer)
    @request_referer = request_referer
    super(current_user, params)
  end

  def call(&)
    ensure_default_filters
    @fund_defaulted = false
    ensure_default_fund
    @q = AccountEntry.ransack(@params[:q])

    @account_entries = apply_policy_scope(@q.result, &)
    @account_entries = @account_entries.preload(:fund, :investor, :investor_kyc, capital_commitment: :investor_kyc)

    sort_by_id_then_existing
    filter_index

    @fund = Fund.find(@params[:fund_id]) if @params[:fund_id].present?

    Result.new(build_result_attributes)
  end

  private

  # Open on the user's first fund (the entity's own fund ordering) instead of every fund of the
  # entity: with all funds the database sorts and de-duplicates the whole ledger. Only applies
  # when the request names no fund and is not already narrowed by another filter (see
  # NARROWING_ATTRIBUTES); any fund (or funds) the user picks is left exactly as given.
  #
  # "All Funds" in the top filter submits fund_id= (key present, blank), so a present key means
  # the user chose that on purpose. A fresh page load has no fund_id key at all.
  #
  # Written into params[:fund_id], exactly as if the user had picked the fund in the top
  # "Fund Name" filter, so that filter shows the fund's name and the links built from the
  # params ("Delete Results", paging, New Account Entry) carry it. The page tells the user
  # which fund is shown (fund_defaulted).
  def ensure_default_fund
    # fund_id is in the URL: a fund was picked, or "All Funds" (fund_id=) was chosen on purpose.
    return if @params.key?(:fund_id)
    return if NARROWING_ATTRIBUTES.any? { |name| @params[name].present? }

    # No fund_id in the URL (menu link, bookmark, fresh load), but a fund or narrowing
    # condition in q.
    wanted = ['fund_id'] + NARROWING_ATTRIBUTES
    condition_given = AccountEntry.ransack(@params[:q]).conditions.any? do |condition|
      condition.attributes.map(&:name).intersect?(wanted)
    end
    return if condition_given

    # Nothing narrows the request: open on the first fund the user can access.
    default_fund = Pundit.policy_scope!(@current_user, Fund).ordered.order("funds.id").first
    return unless default_fund

    @params[:fund_id] = default_fund.id
    @fund_defaulted = true
  end

  # Force a reporting_date lower bound for perf, unless the user already gave one.
  #
  # Ransack accepts params[:q] in two shapes: a simple hash ("reporting_date_gt" => ...)
  # or an "advanced search" condition tree from the search builder UI.
  def ensure_default_filters
    @params[:q] ||= {}

    reporting_date_conditions = AccountEntry.ransack(@params[:q]).conditions.select do |condition|
      condition.attributes.map(&:name).include?('reporting_date')
    end

    # A gt/gteq ("greater than") condition already bounds the query on the left —
    # nothing to do. An eq ("equals") condition pins to a single date, which bounds
    # it too. An lt/lteq ("less than") condition alone does NOT bound the left side,
    # so it doesn't count as already-constrained.
    already_has_lower_bound = reporting_date_conditions.any? { |c| REPORTING_DATE_LOWER_BOUND_PREDICATES.include?(c.predicate_name) || c.predicate_name == 'eq' }
    return if already_has_lower_bound

    # No lower bound: default one in. If the user gave an upper bound, anchor to the
    # start of *that* year (e.g. "before 2026-06-15" -> default "on/after 2026-01-01").
    # Otherwise just use the start of the current year.
    upper_bound = reporting_date_conditions.find { |c| REPORTING_DATE_UPPER_BOUND_PREDICATES.include?(c.predicate_name) }
    year = reporting_date_condition_year(upper_bound) || Time.zone.today.year
    # ISO: ransack parses this back with Date._parse, which is locale-blind and reads
    # slashed dates as dd/mm/yyyy. Jan 1 is symmetric so it never misparsed, but the
    # localized form was still wrong in kind -- see the reporting_date link in RunFormulas.
    @params[:q][:reporting_date_gt] = Date.new(year, 1, 1).to_fs(:db)
  end

  def reporting_date_condition_year(condition)
    return nil unless condition

    Date.parse(condition.values.first&.value.to_s).year
  rescue ArgumentError, TypeError
    nil
  end

  def build_result_attributes
    result_attrs = { q: @q, fund: @fund, fund_defaulted: @fund_defaulted, account_entries: @account_entries }

    if @params[:group_fields].present?
      build_data_frame_result(result_attrs)
    elsif @params[:time_series].present?
      build_time_series_result(result_attrs)
    elsif @params[:pivot] == "true"
      pivot = build_pivot_table
      result_attrs[:pivot] = pivot
      result_attrs[:row_limit_exceeded] = pivot.row_limit_exceeded
    else
      result_attrs[:account_entries] = AccountEntrySearch.perform(@account_entries, @current_user, @params)
      result_attrs[:template] = "index"
    end
    result_attrs
  end

  def build_data_frame_result(result_attrs)
    data_frame = AccountEntryDf.new.df(@account_entries, @current_user, @params)
    result_attrs[:data_frame] = data_frame
    result_attrs[:adhoc_json] = data_frame.to_a.to_json
    result_attrs[:template] = @params[:template].presence || "index"
  end

  def build_time_series_result(result_attrs)
    error = check_time_series_params
    if error
      result_attrs[:error] = error
      result_attrs[:redirect_url] = @request_referer || Rails.application.routes.url_helpers.account_entries_path(params: @params.to_unsafe_h)
    else
      result_attrs[:time_series] = AccountEntryTimeSeries.new(@account_entries).call
    end
  end

  def build_pivot_table
    group_by_param = @params[:group_by] || 'entry_type'
    show_breakdown = @params[:show_breakdown] == "true"
    AccountEntryPivot.new(
      @account_entries,
      group_by: group_by_param,
      show_breakdown: show_breakdown,
      page: @params[:page],
      per_page: @params[:per_page] || 20
    ).call
  end

  def filter_index
    # Step 1: Apply basic equality filters
    @account_entries = filter_params(
      @account_entries,
      :capital_commitment_id,
      :investor_id,
      :import_upload_id,
      :fund_id,
      :entry_type,
      :folio_id,
      :unit_type,
      :cumulative,
      :parent_id,
      :parent_type
    )

    # Step 2: Special case - only fund-level accounts (no capital commitment)
    @account_entries = @account_entries.where(capital_commitment_id: nil) if @params[:fund_accounts_only].present?

    # Step 3: Apply reporting_date range filter (start and/or end)
    filter_range(
      :reporting_date,
      start_date: @params[:reporting_date_start],
      end_date: @params[:reporting_date_end]
    )
  end

  def filter_range(column, start_date:, end_date:)
    return unless start_date.present? || end_date.present?

    @account_entries = if start_date.present? && end_date.present?
                         @account_entries.where(column => start_date..end_date)
                       elsif start_date.present?
                         @account_entries.where("#{column} >= ?", start_date)
                       else # end_date.present?
                         @account_entries.where("#{column} <= ?", end_date)
                       end
  end

  def check_time_series_params
    time_series_error = []

    if @params[:fund_id].blank?
      @params[:fund_id] = @current_user.entity.funds.first&.id
      time_series_error << "Please select a fund."
    end
    # Ensure that folio_id is not nil in the ransack params
    unless @q.conditions.any? { |c| c.attributes.map(&:name).include?('folio_id') }
      # Add a condition to the ransack query where folio_id is XYX
      @params[:q] ||= {}
      @params[:q][:folio_id_eq] = "Please Enter Folio ID"
      # Redirect to the current path with notice
      time_series_error << "Please select a folio."
    end

    unless @q.conditions.any? { |c| c.attributes.map(&:name).include?('reporting_date') }
      # Add a condition to the ransack query where folio_id is XYX
      @params[:q] ||= {}
      @params[:q][:reporting_date] = Time.zone.today
      # Redirect to the current path with notice
      time_series_error << "Please select a reporting date."
    end

    time_series_error.presence&.join(" ")
  end

  def sort_by_id_then_existing
    # Pull whatever ORDER BY ransack already applied
    existing_orders = @account_entries.order_values
    # e.g. [#<Arel::Nodes::Ascending ...>, #<Arel::Nodes::Descending ...>, ...]
    # or sometimes [] / [nil] / [""]

    # Clean obvious junk like nil/"" so we don't pass them back
    clean_orders = existing_orders.reject { |frag| frag.respond_to?(:blank?) ? frag.blank? : frag.nil? }

    if clean_orders.present?
      # Does the primary sort already include id? (either as symbol or SQL/Arel)
      includes_id =
        clean_orders.any? do |frag|
          frag.to_s.match?(/\baccount_entries\.id\b/i) || frag == :id || frag == "id"
        end

      @account_entries = if includes_id
                           # We already have id in the sort, so just reapply ransack's order
                           @account_entries.reorder(clean_orders)
                         else
                           # Reapply ransack's full order first, then add id as a stable tiebreaker
                           @account_entries.reorder(clean_orders).order("account_entries.id ASC")
                         end
    else
      # Ransack gave us no order at all → default to id
      @account_entries = @account_entries.reorder(nil).order("account_entries.id ASC")
    end
  end
end
