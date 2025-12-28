class AccountEntryPivot
  attr_reader :rows, :groups, :dates_by_group, :structured_data, :pagy

  def initialize(account_entries, group_by:, show_breakdown: true, page: nil, per_page: 20)
    # We strip out order and includes to prevent the database from doing unnecessary work
    # while we are just gathering metadata for pagination and structure.
    @account_entries = account_entries.except(:includes, :order)
    @group_by_field = group_by.to_sym
    @show_breakdown = show_breakdown
    @page = page
    @per_page = per_page
  end

  def call
    # 1. Determine all unique rows for pagination using a minimal pluck
    # This avoids loading any full ActiveRecord objects.
    all_rows = if @show_breakdown
                 @account_entries.distinct
                                 .pluck(:commitment_name, :capital_commitment_id, :parent_name, :parent_type, :parent_id)
               else
                 @account_entries.distinct
                                 .pluck(:commitment_name, :capital_commitment_id)
                                 .map { |name, id| [name, id, nil, nil, nil] }
               end

    # 2. Apply Pagination to Rows
    page_num = (@page.presence || 1).to_i
    per_page_num = (@per_page.presence || 20).to_i

    if page_num.positive?
      @pagy = Pagy.new(count: all_rows.size, page: page_num, items: per_page_num)
      limit = @pagy.respond_to?(:limit) ? @pagy.limit : @pagy.vars[:items]
      @rows = all_rows[@pagy.offset, limit] || []
    else
      @rows = all_rows
    end

    # 3. Fetch ONLY the specific columns needed for the current page
    # This is the biggest memory saver: we don't fetch full AccountEntry objects or join capital_commitments
    # We only fetch the identifiers, the group_by field, the date, and the amount.
    @structured_data = Hash.new { |h, k| h[k] = Hash.new { |h2, k2| h2[k2] = {} } }

    if @rows.any?
      # Build targeted query
      selection = [:commitment_name, :capital_commitment_id, :parent_name, :parent_type, :parent_id, @group_by_field, :reporting_date, :amount_cents]

      paginated_query = if @show_breakdown
                          row_conditions = @rows.map { |r| { capital_commitment_id: r[1], parent_id: r[4] } }
                          or_conditions = row_conditions.map { |c| "(capital_commitment_id = #{c[:capital_commitment_id].to_i} AND parent_id = #{c[:parent_id].to_i})" }.join(" OR ")
                          @account_entries.where(or_conditions)
                        else
                          commitment_ids = @rows.filter_map { |r| r[1] }
                          @account_entries.where(capital_commitment_id: commitment_ids)
                        end

      # We use pluck to get raw data instead of ActiveRecord objects
      paginated_query.pluck(*selection).each do |c_name, c_id, p_name, p_type, p_id, group_val, date, amount_cents|
        key = if @show_breakdown
                [c_name, c_id, p_name, p_type, p_id]
              else
                [c_name, c_id, nil, nil, nil]
              end

        # We store minimal OpenStructs or even just hashes to save memory
        # The view expects amount, reporting_date, etc.
        amount = amount_cents.to_f / 100.0

        if @show_breakdown
          @structured_data[key][group_val][date] = OpenStruct.new(amount: amount, reporting_date: date)
        else
          @structured_data[key][group_val][date] ||= OpenStruct.new(amount: 0, reporting_date: date, commitment_name: c_name, capital_commitment_id: c_id)
          @structured_data[key][group_val][date].amount += amount
        end
      end
    end

    # 4. Consistent Columns (Groups/Dates) - Minimal memory footprint
    group_dates = @account_entries.distinct.pluck(@group_by_field, :reporting_date)
    @groups = group_dates.map(&:first).uniq
    @dates_by_group = {}
    @groups.each do |group|
      @dates_by_group[group] = group_dates.select { |g, _| g == group }.map(&:last).sort
    end

    self
  end

  def chart
    chart_data = []
    @rows.each do |row|
      commitment_name, _commitment_id, parent_name, = row
      row_name = "#{commitment_name} - #{parent_name}"
      row_data = {}

      @groups.each do |group|
        @dates_by_group[group].each do |date|
          entry_obj = @structured_data.dig(row, group, date)
          row_data[date] ||= 0
          row_data[date] += entry_obj.amount.to_f if entry_obj&.amount.present?
        end
      end
      chart_data << { name: row_name, data: row_data.sort.to_h }
    end
    chart_data
  end
end
