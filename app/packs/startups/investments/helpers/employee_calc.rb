class EmployeeCalc
  attr_accessor :params, :current_user, :price_growth, :tax_rate, :estimated_taxes, :estimated_profit,
                :cost_neutral_sale, :last_valuation, :esop_value, :all_or_vested, :total_value, :total_profit

  def initialize(params, current_user)
    @price_growth, @tax_rate, @estimated_taxes, @estimated_profit,
    @cost_neutral_sale, @last_valuation, @esop_value =
      HoldingSummary.new(params, current_user).employee_summary
    @params = params
  end
end
