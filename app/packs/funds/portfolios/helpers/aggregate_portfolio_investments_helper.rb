module AggregatePortfolioInvestmentsHelper
  def investment_fmv_by_company(fund)
    portfolio_investments = fund.portfolio_investments.includes(:portfolio_company).group(:investor_name).sum(:fmv_cents)
    grouped = portfolio_investments.map { |name, fmv_cents| [name, fmv_cents / 100] }

    pie_chart_with_options grouped
  end

  def investment_bought_by_company(fund)
    portfolio_investments = fund.portfolio_investments.buys.where(quantity: 0..).includes(:portfolio_company).group(:investor_name).sum(:amount_cents)
    grouped = portfolio_investments.map { |name, amount_cents| [name, amount_cents / 100] }

    pie_chart_with_options grouped
  end

  def investment_sold_by_company(fund)
    portfolio_investments = fund.portfolio_investments.sells.includes(:portfolio_company).group(:investor_name).sum(:amount_cents)
    grouped = portfolio_investments.map { |name, amount_cents| [name, amount_cents / 100] }

    pie_chart_with_options grouped
  end

  def investment_holding_cost_by_company(fund)
    portfolio_investments = fund.portfolio_investments.buys.group_by(&:portfolio_company_name)

    grouped = portfolio_investments.transform_values do |pis|
      pis.sum { |pi| pi.net_quantity * pi.cost.to_d }
    end

    pie_chart_with_options grouped
  end

  def bought_sold_fmv(fund)
    aggregate_portfolio_investments = fund.aggregate_portfolio_investments
    grouped = aggregate_portfolio_investments
              .map { |k| [k.portfolio_company_name, k.fmv.to_d, k.bought_amount.to_d, k.sold_amount.to_d] }

    column_chart [
      { name: "Bought", data: grouped.map { |k| [k[0], k[2]] } },
      { name: "Sold", data: grouped.map { |k| [k[0], k[3]] } },
      { name: "FMV", data: grouped.map { |k| [k[0], k[1]] } }
    ], library: {
      plotOptions: {
        column: {
          pointWidth: 40,
          dataLabels: {
            enabled: false,
            format: "{point.y:,.2f}"
          }
        }
      },
      **chart_theme_color
    }
  end

  def buy_sell_timeline(fund)
    buy_data = fund.portfolio_investments.buys.group_by { |pi| pi.investment_date.year }.map { |k, arr| [k, arr.inject(0) { |sum, element| sum + element.amount.to_d }] }

    sell_data = fund.portfolio_investments.sells.group_by { |pi| pi.investment_date.year }.map { |k, arr| [k, arr.inject(0) { |sum, element| sum + element.amount.to_d }] }

    column_chart [{ name: "Buys", data: buy_data }, { name: "Sells", data: sell_data }], library: {
      plotOptions: {
        column: {
          pointWidth: 40,
          dataLabels: {
            enabled: false,
            format: "{point.y:,.2f}"
          }
        }
      },
      **chart_theme_color
    }
  end
end
