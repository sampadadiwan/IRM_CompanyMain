module AggregateInvestmentsHelper
  def calculate_scenario(entity, params)
    total_stake = params[:pre_money_valuation].to_f + params[:amount].to_f
    stake = total_stake.positive? ? (params[:amount].to_f / total_stake) : 0

    aggregate_investments = []
    ai = Struct.new(:investor_name, :percentage, :full_diluted_percentage)

    entity.aggregate_investments.includes(:investor).find_each do |aggregate_investment|
      new_ai = ai.new(aggregate_investment.investor_name, (aggregate_investment.percentage * (1 - stake)).round(2), (aggregate_investment.full_diluted_percentage * (1 - stake)).round(2))

      aggregate_investments << new_ai
    end

    aggregate_investments << ai.new("New Investor", (stake * 100).round(2), (stake * 100).round(2))

    [(stake * 100).round(2), aggregate_investments]
  end
end
