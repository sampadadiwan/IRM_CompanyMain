class AggregatePortfolioInvestmentTimeSeries
  def initialize(apis, fields)
    @apis = apis
    @fields = fields
  end

  def call
    time_series = Hash.new { |h, k| h[k] = {} }

    @apis.includes(:portfolio_company).order(portfolio_company: { investor_name: :asc }).each do |api|
      @fields.each do |field|
        date = api.snapshot_date || Time.zone.today
        time_series[api.orignal_id][:api] ||= api
        time_series[api.orignal_id][:dates] ||= {}
        time_series[api.orignal_id][:dates][date] ||= {}
        time_series[api.orignal_id][:dates][date][field] = api.public_send(field)
      end
    end

    time_series
  end
end
