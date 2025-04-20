class FundRatioPivot
  attr_reader :funds, :owners_by_fund, :dates, :names_by_date, :structured_data

  def initialize(fund_ratios)
    @fund_ratios = fund_ratios
  end

  def call
    # Build structure: { fund => { owner => { date => { name => value } } } }
    @structured_data = Hash.new do |fund_hash, fund|
      fund_hash[fund] = Hash.new do |owner_hash, owner|
        owner_hash[owner] = Hash.new { |date_hash, date| date_hash[date] = {} }
      end
    end

    @fund_ratios.each do |fr|
      fund = fr.fund
      owner = fr.owner
      date = fr.end_date
      name = fr.name

      @structured_data[fund][owner][date][name] = fr.display_value
    end

    @funds = @structured_data.keys

    @owners_by_fund = {}
    @structured_data.each do |fund, owners|
      @owners_by_fund[fund] = owners.keys
    end

    @dates = @fund_ratios.map(&:end_date).uniq.sort

    @names_by_date = {}
    @dates.each do |date|
      @names_by_date[date] = @fund_ratios.select { |fr| fr.end_date == date }.map(&:name).uniq
    end

    self
  end
end
