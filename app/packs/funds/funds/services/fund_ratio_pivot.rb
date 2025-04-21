class FundRatioPivot
  attr_reader :funds, :owners_by_fund, :periods, :names_by_period, :structured_data

  def initialize(fund_ratios, group_by_period: :month)
    @fund_ratios = fund_ratios
    @group_by_period = group_by_period.to_sym # :month or :quarter
  end

  def call
    @structured_data = Hash.new do |fund_hash, fund|
      fund_hash[fund] = Hash.new do |owner_hash, owner|
        owner_hash[owner] = Hash.new { |period_hash, period| period_hash[period] = {} }
      end
    end

    @fund_ratios.each do |fr|
      fund = fr.fund
      owner = fr.owner
      period = format_period(fr.end_date)
      name = fr.name

      @structured_data[fund][owner][period][name] = fr.display_value
    end

    @funds = @structured_data.keys

    @owners_by_fund = {}
    @structured_data.each do |fund, owners|
      @owners_by_fund[fund] = owners.keys
    end

    @periods = @fund_ratios.map { |fr| format_period(fr.end_date) }.uniq.sort_by { |p| period_sort_key(p) }

    @names_by_period = {}
    @periods.each do |period|
      @names_by_period[period] = @fund_ratios.select { |fr| format_period(fr.end_date) == period }.map(&:name).uniq
    end

    self
  end

  private

  def format_period(date)
    case @group_by_period
    when :month
      date.strftime("%b %Y") # => "Jan 2024"
    when :quarter
      quarter = ((date.month - 1) / 3) + 1
      "Q#{quarter} #{date.year}" # => "Q1 2024"
    else
      raise ArgumentError, "Unsupported group_by_period: #{@group_by_period}"
    end
  end

  def period_sort_key(period)
    if period =~ /^Q(\d) (\d{4})$/
      year = ::Regexp.last_match(2).to_i
      quarter = ::Regexp.last_match(1).to_i
      [year, quarter]
    elsif period =~ /^([A-Za-z]+) (\d{4})$/
      year = ::Regexp.last_match(2).to_i
      month = Date::ABBR_MONTHNAMES.index(::Regexp.last_match(1))
      [year, month]
    else
      [0, 0] # fallback for unknown
    end
  end
end
