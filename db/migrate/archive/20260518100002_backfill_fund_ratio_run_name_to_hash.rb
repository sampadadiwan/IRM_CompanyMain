class BackfillFundRatioRunNameToHash < ActiveRecord::Migration[7.2]
  def up
    FundRatioRun.find_each do |run|
      run.update_columns(
        name: FundRatioRun.fingerprint(
          fund_ids:              run.fund_ids,
          portfolio_company_ids: run.portfolio_company_ids,
          tags:                  run.portfolio_companies_tags,
          sectors:               run.sectors
        )
      )
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
