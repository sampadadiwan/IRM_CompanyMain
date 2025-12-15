# Service for listing and filtering Account Entries.
#
# This service encapsulates the logic for Ransack search, Pundit scoping,
# custom filters, time series generation, and pivot tables used in the
# AccountEntriesController index action.
#
# It ensures that a policy scope is always applied to the query:
# 1. If a block is given, it yields the relation to the block (allowing controllers to use `policy_scope` helper).
# 2. If no block is given, it uses `Pundit.policy_scope!` directly.
class AccountEntryList
  Result = Struct.new(:q, :account_entries, :fund, :data_frame, :adhoc_json, :template, :time_series, :pivot, :error, :redirect_url, keyword_init: true)

  # @param current_user [User] The user performing the action.
  # @param params [Hash] The parameters for filtering and search.
  # @param request_referer [String] Optional referer URL for redirects on error.
  # @yield [relation] Optional block for applying policy scope.
  def self.call(current_user, params, request_referer = nil, &)
    new(current_user, params, request_referer).call(&)
  end

  def initialize(current_user, params, request_referer)
    @current_user = current_user
    @params = params
    @request_referer = request_referer
  end

  def call
    ensure_default_filters
    @q = AccountEntry.ransack(@params[:q])

    resolve_scope { |relation| block_given? ? yield(relation) : relation }

    sort_by_id_then_existing
    filter_index

    @fund = Fund.find(@params[:fund_id]) if @params[:fund_id].present?

    Result.new(build_result_attributes)
  end

  private

  def ensure_default_filters
    @params[:q] ||= {}
    # Force reporting_date filter for perf if user didn't constrain reporting_date
    return if ransack_has_attr?(@params[:q], 'reporting_date')

    @params[:q][:reporting_date_gt] = I18n.l(Time.zone.today.beginning_of_year)
  end

  def resolve_scope
    scope = @q.result
    scope = if block_given?
              yield(scope)
            else
              Pundit.policy_scope!(@current_user, scope)
            end
    @account_entries = scope.includes(:capital_commitment, :fund)
  end

  def build_result_attributes
    result_attrs = { q: @q, fund: @fund, account_entries: @account_entries }

    if @params[:group_fields].present?
      build_data_frame_result(result_attrs)
    elsif @params[:time_series].present?
      build_time_series_result(result_attrs)
    elsif @params[:pivot] == "true"
      result_attrs[:pivot] = build_pivot_table
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
    AccountEntryPivot.new(@account_entries.includes(:fund), group_by: group_by_param, show_breakdown:).call
  end

  def simple_predicate_match?(query_hash, attrs)
    query_hash.any? { |k, _| attrs.any? { |a| k.to_s == a || k.to_s.start_with?("#{a}_") } }
  end

  def advanced_condition_match?(query_hash, attrs)
    queue = [query_hash]
    while (node = queue.shift)
      [node['c'], node[:c], node['g'], node[:g]].compact.each do |children|
        children_list = children.is_a?(Hash) ? children.values : Array(children)

        children_list.each do |item|
          item_hash = item.is_a?(Hash) ? item : nil
          next unless item_hash

          queue << item_hash if item_hash.key?('c') || item_hash.key?(:c) || item_hash.key?('g') || item_hash.key?(:g)

          return true if check_attributes_match(item_hash, attrs)
        end
      end
    end
    false
  end

  def check_attributes_match(item, attrs)
    a_field = item['a'] || item[:a]
    a_list = case a_field
             when Hash then a_field.values
             when Array then a_field
             else []
             end

    names = a_list.filter_map { |h| h.is_a?(Hash) ? (h['name'] || h[:name] || h['value'] || h[:value]) : h }.map(&:to_s)
    names.any? { |n| attrs.any? { |a| n == a || n.start_with?("#{a}_") || n.end_with?("_#{a}") } }
  end

  def filter_index
    # Step 1: Apply basic equality filters
    filter_params(
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

  def filter_params(*keys)
    keys.each do |key|
      @account_entries = @account_entries.where(key => @params[key]) if @params[key].present?
    end
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

  # Checks whether Ransack params include any of the given attribute names.
  def ransack_has_attr?(q_param, attrs)
    return false if q_param.blank?

    query_hash = q_param.respond_to?(:to_unsafe_h) ? q_param.to_unsafe_h : q_param
    attrs = Array(attrs).map!(&:to_s)

    return true if simple_predicate_match?(query_hash, attrs)

    advanced_condition_match?(query_hash, attrs)
  end
end
