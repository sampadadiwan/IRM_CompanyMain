class AddAccountEntryNamesToReport < ActiveRecord::Migration[8.0]
  def down
    remove_column :reports, :metadata
    remove_column :account_entries, :parent_name
    remove_column :account_entries, :commitment_name
  end

  def up
    add_column :reports, :metadata, :text
    add_column :account_entries, :parent_name, :string
    add_column :account_entries, :commitment_name, :string
  end

  def update_old_date

    # AccountEntry.includes(:fund_formula).all.each do |entry|
    #   entry.setup_defaults
    #   entry.name = entry.fund_formula.name 
    #   entry.entry_type = entry.fund_formula.entry_type   
    #   entry.save(validate: false)
    # end


    puts "Updating account entries with fund formula names and entry types"
    AccountEntry.joins(:fund_formula).update_all("account_entries.name=fund_formulas.name, account_entries.entry_type=fund_formulas.entry_type")

    puts "Updating account entries with parent names for capital commitments"
    ActiveRecord::Base.connection.execute("UPDATE account_entries ae
    JOIN capital_commitments cc ON ae.capital_commitment_id = cc.id
    JOIN investor_kycs ik ON cc.investor_kyc_id = ik.id
    SET ae.commitment_name = LEFT(CONCAT(ik.full_name, ' - ', cc.folio_id), 255)
    WHERE ae.capital_commitment_id IS NOT NULL;")

    puts "Updating account entries with parent names for portfolio investments"
    ActiveRecord::Base.connection.execute("UPDATE account_entries ae
      JOIN portfolio_investments pi ON ae.parent_id = pi.id
      JOIN investment_instruments ii ON pi.investment_instrument_id = ii.id
      SET ae.parent_name = LEFT(
        CONCAT_WS(' ',
          pi.portfolio_company_name,
          ii.name,
          CASE WHEN pi.quantity > 0 THEN 'Buy' ELSE 'Sell' END,
          DATE_FORMAT(pi.investment_date, '%d/%m/%Y')
        ), 255
      )
      WHERE ae.parent_type = 'PortfolioInvestment';")

      puts "Updating account entries with parent names for aggregate portfolio investments"
      ActiveRecord::Base.connection.execute("UPDATE account_entries ae
        JOIN aggregate_portfolio_investments api ON ae.parent_id = api.id
        JOIN investment_instruments ii ON api.investment_instrument_id = ii.id
        SET ae.parent_name = LEFT(
          CONCAT_WS(' ',
            api.portfolio_company_name,
            ii.name
          ), 255
        )
        WHERE ae.parent_type = 'AggregatePortfolioInvestment';")

      puts "Updating account entries with parent names for account entries"
      ActiveRecord::Base.connection.execute("UPDATE account_entries ae
          JOIN account_entries parent ON ae.parent_id = parent.id
          SET ae.parent_name = LEFT(
            CONCAT_WS(' ',              
              parent.name,
              DATE_FORMAT(parent.reporting_date, '%d/%m/%Y')
            ), 255
          )
          WHERE ae.parent_type = 'AccountEntry';")
  end
end
