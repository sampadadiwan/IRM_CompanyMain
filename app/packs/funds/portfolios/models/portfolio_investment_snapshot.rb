class PortfolioInvestmentSnapshot < PortfolioInvestmentBase
  # This has all the utility methods required for snashots
  include WithSnapshot

  belongs_to :fund,
             lambda { |snapshot|
               where(snapshot_date: snapshot.snapshot_date)
             },
             class_name: "FundSnapshot",
             foreign_key: :fund_id,
             primary_key: :id

  belongs_to :aggregate_portfolio_investment,
             lambda { |snapshot|
               where(snapshot_date: snapshot.snapshot_date)
             },
             class_name: "AggregatePortfolioInvestmentSnapshot",
             foreign_key: :aggregate_portfolio_investment_id,
             primary_key: :id
end
