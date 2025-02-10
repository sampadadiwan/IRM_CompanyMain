class AggregatePortfolioInvestmentsDatatable < ApplicationDatatable
  def view_columns
    @view_columns ||= {
      id: { source: "AggregatePortfolioInvestment.id" },
      fund_name: { source: "Fund.name" },
      portfolio_company_name: { source: "AggregatePortfolioInvestment.portfolio_company_name" },
      investment_instrument: { source: "InvestmentInstrument.name" },
      bought_amount: { source: "AggregatePortfolioInvestment.net_bought_amount_cents" },
      sold_amount: { source: "AggregatePortfolioInvestment.sold_amount_cents" },
      current_quantity: { source: "AggregatePortfolioInvestment.quantity" },
      fmv: { source: "AggregatePortfolioInvestment.fmv_cents" },
      avg_cost: { source: "AggregatePortfolioInvestment.avg_cost_cents" },
      dt_actions: { source: "", orderable: false }
    }
  end

  def data
    records.map do |record|
      {
        id: record.id,
        fund_name: record.decorate.fund_name,
        portfolio_company_name: record.decorate.company_link,
        investment_instrument: record.decorate.investment_instrument,
        bought_amount: record.decorate.money_to_currency(record.net_bought_amount, params),
        sold_amount: record.decorate.money_to_currency(record.sold_amount, params),
        current_quantity: record.quantity,
        fmv: record.decorate.money_to_currency(record.fmv, params),
        avg_cost: record.decorate.money_to_currency(record.avg_cost, params),
        dt_actions: record.decorate.dt_actions,
        DT_RowId: "aggregate_portfolio_investment_#{record.id}"
      }
    end
  end

  def aggregate_portfolio_investments
    @aggregate_portfolio_investments ||= options[:aggregate_portfolio_investments]
  end

  def get_raw_records
    aggregate_portfolio_investments
  end

  def search_for
    []
  end
end
