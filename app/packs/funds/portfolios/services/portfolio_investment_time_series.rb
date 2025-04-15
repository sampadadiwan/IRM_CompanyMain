class PortfolioInvestmentTimeSeries
  def initialize(investments, fields)
    @investments = investments
    @fields = fields
  end

  def call
    time_series = Hash.new { |h, k| h[k] = {} }

    @investments.order(:investment_date).each do |investment|
      @fields.each do |field|
        date = investment.snapshot_date || Time.zone.today
        time_series[investment][date] ||= {}
        time_series[investment][date][field] = investment.public_send(field)
      end
    end

    time_series
  end
end
