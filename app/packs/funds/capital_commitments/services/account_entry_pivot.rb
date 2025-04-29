class AccountEntryPivot
  attr_reader :rows, :groups, :dates_by_group, :structured_data

  def initialize(account_entries, group_by:, parent_in_key: true)
    @account_entries = account_entries
    @group_by_field = group_by.to_sym
    @parent_in_key = parent_in_key
  end

  def call
    # structured_data: { [commitment, parent] => { group => { date => amount } } }
    @structured_data = Hash.new { |h, k| h[k] = Hash.new { |h2, k2| h2[k2] = {} } }

    @account_entries.each do |entry|
      key = if @parent_in_key
              [entry.commitment_name, entry.capital_commitment_id, entry.parent_name, entry.parent_type, entry.parent_id]
            else
              [entry.commitment_name, entry.capital_commitment_id, nil, nil, nil]
            end
      group = entry.public_send(@group_by_field)
      @structured_data[key][group][entry.reporting_date] = entry.amount
    end

    @rows = @structured_data.keys # array of [commitment_name, parent]
    @groups = @account_entries.map { |e| e.public_send(@group_by_field) }.uniq

    @dates_by_group = {}
    @groups.each do |group|
      @dates_by_group[group] = @structured_data.values.flat_map do |group_map|
        group_map[group]&.keys || []
      end.uniq.sort
    end

    self
  end

  def chart
    chart_data = [] # Initialize an array to hold the chart data

    @rows.each do |row| # Iterate over each row (key) in the structured data
      # Destructure the row to extract commitment and parent details
      commitment_name, _commitment_id, parent_name, = row
      # Create a label for the row by combining commitment and parent names
      row_name = "#{commitment_name} - #{parent_name}"

      row_data = {} # Initialize a hash to hold the data for this row

      @groups.each do |group| # Iterate over each group
        @dates_by_group[group].each do |date| # Iterate over each date in the group
          # Retrieve the amount for the current row, group, and date
          amount = @structured_data.dig(row, group, date)
          row_data[date] ||= 0 # Initialize the date key in row_data if not already present
          # Add the amount to the date key, converting to float and checking presence
          row_data[date] += amount.to_f if amount.present?
        end
      end

      # Add the row's data to the chart_data array, sorting the dates
      chart_data << { name: row_name, data: row_data.sort.to_h }
    end

    chart_data
  end
end
