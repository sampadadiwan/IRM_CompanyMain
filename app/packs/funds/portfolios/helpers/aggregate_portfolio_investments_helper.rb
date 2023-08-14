module AggregatePortfolioInvestmentsHelper
  def investment_fmv_by_company(fund)
    aggregate_portfolio_investments = fund.aggregate_portfolio_investments
    grouped = aggregate_portfolio_investments
              .map { |k| [k.portfolio_company_name, k.fmv.to_d] }

    pie_chart_with_options grouped
  end

  def investment_bought_by_company(fund)
    aggregate_portfolio_investments = fund.aggregate_portfolio_investments
    grouped = aggregate_portfolio_investments
              .map { |k| [k.portfolio_company_name, k.bought_amount.to_d] }

    pie_chart_with_options grouped
  end

  def investment_sold_by_company(fund)
    aggregate_portfolio_investments = fund.aggregate_portfolio_investments
    grouped = aggregate_portfolio_investments
              .map { |k| [k.portfolio_company_name, k.sold_amount.to_d] }

    pie_chart_with_options grouped
  end

  def investment_holding_cost_by_company(fund)
    aggregate_portfolio_investments = fund.aggregate_portfolio_investments
    grouped = aggregate_portfolio_investments
              .map { |k| [k.portfolio_company_name, k.quantity * k.avg_cost.to_d] }

    pie_chart_with_options grouped
  end

  def bought_sold_fmv(fund)
    aggregate_portfolio_investments = fund.aggregate_portfolio_investments
    grouped = aggregate_portfolio_investments
              .map { |k| [k.portfolio_company_name, k.fmv.to_d, k.bought_amount.to_d, k.sold_amount.to_d] }

    column_chart [
      { name: "FMV", data: grouped.map { |k| [k[0], k[1]] } },
      { name: "Bought", data: grouped.map { |k| [k[0], k[2]] } },
      { name: "Sold", data: grouped.map { |k| [k[0], k[3]] } }
    ]
  end

  def buy_sell_timeline(fund)
    buy_data = fund.portfolio_investments.buys.group_by { |pi| pi.investment_date.year }.map { |k, arr| [k, arr.inject(0) { |sum, element| sum + element.amount.to_d }] }

    sell_data = fund.portfolio_investments.sells.group_by { |pi| pi.investment_date.year }.map { |k, arr| [k, arr.inject(0) { |sum, element| sum + element.amount.to_d }] }

    column_chart [{ name: "Buys", data: buy_data }, { name: "Sells", data: sell_data }]
  end
end
