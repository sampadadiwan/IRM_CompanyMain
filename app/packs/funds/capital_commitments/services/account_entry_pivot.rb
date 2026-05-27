class AccountEntryPivot
  # Mutable value object for a single cell in the pivot grid.
  # Struct (not Data.define) because .amount is mutated with += when accumulating
  # multiple account entries into the same cell during the build pass.
  PivotEntry = Struct.new(:amount, :reporting_date, :commitment_name, :capital_commitment_id)
  attr_reader :rows, :groups, :dates_by_group, :structured_data, :pagy, :row_limit_exceeded

  # Strip characters that XML 1.0 forbids (axlsx/libxml raises "out of char range"
  # if a string cell contains them).  Safe for nil/non-string values.
  def self.sanitize_str(val)
    return val unless val.is_a?(String)

    val.encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
       .gsub(/[^\u0009\u000A\u000D\u0020-\uD7FF\uE000-\uFFFD]/u, "")
  end

  def initialize(account_entries, group_by:, show_breakdown: true, page: nil, per_page: 20)
    # We strip out order and includes to prevent the database from doing unnecessary work
    # while we are just gathering metadata for pagination and structure.
    @account_entries = account_entries.except(:includes, :order)
    @group_by_field = group_by.to_sym
    @show_breakdown = show_breakdown
    @page = page
    @per_page = per_page
    @row_limit_exceeded = false
  end

  def call
    # 1. Determine all unique rows for pagination using a minimal pluck
    # This avoids loading any full ActiveRecord objects.
    all_rows = if @show_breakdown
                 @account_entries.distinct
                                 .pluck(:commitment_name, :capital_commitment_id, :parent_name, :parent_type, :parent_id)
                                 .map { |c, id, p, pt, pi| [self.class.sanitize_str(c), id, self.class.sanitize_str(p), self.class.sanitize_str(pt), pi] }
               else
                 @account_entries.distinct
                                 .pluck(:commitment_name, :capital_commitment_id)
                                 .map { |name, id| [self.class.sanitize_str(name), id, nil, nil, nil] }
               end

    # 2. Apply Pagination to Rows
    # Pass page: 0 (or any non-positive value) to disable pagination and return all rows.
    page_num = (@page.presence || 1).to_i
    per_page_num = (@per_page.presence || 20).to_i

    if page_num.positive?
      @pagy = Pagy.new(count: all_rows.size, page: page_num, items: per_page_num)
      limit = @pagy.respond_to?(:limit) ? @pagy.limit : @pagy.vars[:items]
      @rows = all_rows[@pagy.offset, limit] || []
    else
      # page=0 means "no pagination – return all rows" (used by background XLSX export)
      @pagy = nil
      max_rows_without_pagination = 50_000
      if all_rows.size > max_rows_without_pagination
        Rails.logger.warn("[AccountEntryPivot] Truncating rows for unpaginated export: #{all_rows.size} rows exceeds max of #{max_rows_without_pagination}")
        @rows = all_rows.first(max_rows_without_pagination)
        @row_limit_exceeded = true
      else
        @rows = all_rows
      end
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
        c_name    = self.class.sanitize_str(c_name)
        p_name    = self.class.sanitize_str(p_name)
        p_type    = self.class.sanitize_str(p_type)
        group_val = self.class.sanitize_str(group_val)

        key = if @show_breakdown
                [c_name, c_id, p_name, p_type, p_id]
              else
                [c_name, c_id, nil, nil, nil]
              end

        # We store minimal OpenStructs or even just hashes to save memory
        # The view expects amount, reporting_date, etc.
        amount = amount_cents.to_f / 100.0

        if @show_breakdown
          @structured_data[key][group_val][date] = PivotEntry.new(amount, date, nil, nil)
        else
          @structured_data[key][group_val][date] ||= PivotEntry.new(0, date, c_name, c_id)
          @structured_data[key][group_val][date].amount += amount  # Struct accessor allows mutation
        end
      end
    end

    # 4. Consistent Columns (Groups/Dates) - Minimal memory footprint
    group_dates = @account_entries.distinct.pluck(@group_by_field, :reporting_date)
                                  .map { |g, d| [self.class.sanitize_str(g), d] }
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
