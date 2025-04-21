class AccountEntryPivot
  attr_reader :rows, :groups, :dates_by_group, :structured_data

  def initialize(account_entries, group_by:)
    @account_entries = account_entries
    @group_by_field = group_by.to_sym
  end

  def call
    # structured_data: { [commitment, parent] => { group => { date => amount } } }
    @structured_data = Hash.new { |h, k| h[k] = Hash.new { |h2, k2| h2[k2] = {} } }

    @account_entries.each do |entry|
      key = [entry.commitment_name, entry.capital_commitment_id, entry.parent_name, entry.parent_type, entry.parent_id]
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
end
