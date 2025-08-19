class AccountEntryPivot
  attr_reader :rows, :groups, :dates_by_group, :structured_data

  def initialize(account_entries, group_by:, show_breakdown: true)
    @account_entries = account_entries
    @group_by_field = group_by.to_sym
    @show_breakdown = show_breakdown
  end

  def call
    # structured_data: { [commitment_identifier] => { group_by_field_value => { reporting_date => account_entry_object } } }
    # Initializes a nested hash to store structured data.
    # The commitment_identifier is an array that uniquely identifies a commitment, potentially including parent details.
    @structured_data = Hash.new { |h, k| h[k] = Hash.new { |h2, k2| h2[k2] = {} } }

    # Iterates through each account entry to populate the structured_data hash.
    @account_entries.each do |entry|
      # Determines the key for the structured_data hash based on whether breakdown is shown.
      # If @show_breakdown is true, the key includes commitment and parent details for granular data.
      # Otherwise, it only includes commitment details, aggregating data without parent breakdown.
      key = if @show_breakdown
              [entry.commitment_name, entry.capital_commitment_id, entry.parent_name, entry.parent_type, entry.parent_id]
            else
              [entry.commitment_name, entry.capital_commitment_id, nil, nil, nil]
            end
      # Dynamically gets the grouping value (e.g., 'fund', 'quarter') from the entry object.
      group = entry.public_send(@group_by_field)
      # If breakdown is not shown, cumulate amounts for the same group and reporting_date.
      if @show_breakdown
        @structured_data[key][group][entry.reporting_date] = entry
      else
        # Initialize a dummy entry if none exists to accumulate amounts.
        unless @structured_data[key][group][entry.reporting_date]
          dummy_entry = OpenStruct.new(amount: 0, reporting_date: entry.reporting_date, commitment_name: entry.commitment_name, capital_commitment_id: entry.capital_commitment_id)
          @structured_data[key][group][entry.reporting_date] = dummy_entry
        end
        # Add the current entry's amount to the cumulated amount.
        @structured_data[key][group][entry.reporting_date].amount += entry.amount.to_f
      end
    end

    # Extracts unique row identifiers from the structured data.
    # Each row represents a unique commitment (and potentially parent, if breakdown is enabled).
    @rows = @structured_data.keys # Array of [commitment_name, capital_commitment_id, parent_name, parent_type, parent_id]

    # Extracts unique grouping values (e.g., 'fund names', 'quarters') from all account entries.
    @groups = @account_entries.map { |e| e.public_send(@group_by_field) }.uniq

    # Initializes a hash to store unique sorted dates for each group.
    @dates_by_group = {}
    # Populates @dates_by_group: for each group, collects all unique reporting dates present in the structured data.
    @groups.each do |group|
      @dates_by_group[group] = @structured_data.values.flat_map do |group_map|
        # For each commitment's data, retrieve dates associated with the current group.
        # Use `&.keys || []` to safely handle cases where a group might not have entries for a specific commitment.
        group_map[group]&.keys || []
      end.uniq.sort # Ensures dates are unique and sorted chronologically.
    end

    self # Returns the instance of the object, allowing for method chaining.
  end

  def chart
    # Initializes an array to hold the final chart data, where each element will represent a series.
    chart_data = []

    # Iterates over each unique row (commitment or commitment-parent combination) identified in the #call method.
    @rows.each do |row|
      # Destructures the row array to extract the commitment name and parent name.
      # _commitment_id is ignored as it's not used in the row_name.
      commitment_name, _commitment_id, parent_name, = row
      # Creates a human-readable label for the current row, combining commitment and parent names.
      row_name = "#{commitment_name} - #{parent_name}"

      # Initializes a hash to accumulate data points (date => amount) for the current row.
      row_data = {}

      # Iterates over each unique group (e.g., 'fund', 'quarter') defined in the #call method.
      @groups.each do |group|
        # For each group, iterates over its associated unique and sorted reporting dates.
        @dates_by_group[group].each do |date|
          # Safely retrieves the account_entry object for the current row, group, and date.
          # `dig` is used for safe navigation through nested hashes.
          entry_obj = @structured_data.dig(row, group, date)
          # Initializes the amount for the current date to 0 if it hasn't been set yet.
          # This ensures that dates with no entries explicitly get a zero value.
          row_data[date] ||= 0
          # If an account_entry object exists and has a present amount,
          # its float value is added to the total for the current date in row_data.
          row_data[date] += entry_obj.amount.to_f if entry_obj&.amount.present?
        end
      end

      # Appends the aggregated data for the current row to the chart_data array.
      # The `row_data` hash is sorted by date (key) and converted back to a hash to maintain order.
      chart_data << { name: row_name, data: row_data.sort.to_h }
    end

    # Returns the complete chart data, formatted for charting libraries.
    chart_data
  end
end
