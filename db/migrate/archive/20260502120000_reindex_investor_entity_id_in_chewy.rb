class ReindexInvestorEntityIdInChewy < ActiveRecord::Migration[7.2]
  def up
    [
      CapitalCommitmentIndex,
      CapitalDistributionPaymentIndex,
      CapitalRemittanceIndex,
      AggregatePortfolioInvestmentIndex
    ].each(&:reset!)
  end

  def down
    # No-op: reindexing is not reversible
  end
end
