class AggregatePortfolioInvestmentSnapshot < AggregatePortfolioInvestmentBase
  include WithSnapshot
  belongs_to :entity
  belongs_to :fund,
             lambda { |snapshot|
               where(snapshot_date: snapshot.snapshot_date)
             },
             class_name: "FundSnapshot",
             foreign_key: :fund_id,
             primary_key: :id

  has_many :portfolio_investments,
           lambda { |snapshot|
             where(snapshot_date: snapshot.snapshot_date)
           },
           class_name: "PortfolioInvestmentSnapshot",
           foreign_key: :aggregate_portfolio_investment_id,
           primary_key: :id, dependent: :destroy

  def to_s
    "#{portfolio_company_name}  #{investment_instrument} - Snashot: #{snapshot_date}"
  end
end
