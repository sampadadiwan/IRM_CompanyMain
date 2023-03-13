class AddFolioCurrencyToCapitalCommitment < ActiveRecord::Migration[7.0]
  def change
    add_column :capital_commitments, :folio_currency, :string, limit: 5
    add_column :capital_commitments, :folio_committed_amount_cents, :decimal, precision: 20, scale: 2, default: "0.0"
    
    add_column :capital_remittances, :folio_call_amount_cents, :decimal, precision: 20, scale: 2, default: "0.0"
    add_column :capital_remittances, :folio_collected_amount_cents, :decimal, precision: 20, scale: 2, default: "0.0"
    add_column :capital_remittances, :folio_committed_amount_cents, :decimal, precision: 20, scale: 2, default: "0.0"

    add_column :capital_remittance_payments, :folio_amount_cents, :decimal, precision: 20, scale: 2, default: "0.0"

    add_column :capital_distribution_payments, :folio_amount_cents, :decimal, precision: 20, scale: 2, default: "0.0"

    add_column :account_entries, :folio_amount_cents, :decimal, precision: 20, scale: 2, default: "0.0"

    CapitalCommitment.all.each do |cc|
      cc.folio_currency = cc.fund.currency
      cc.folio_committed_amount_cents = cc.committed_amount_cents
      cc.save
    end

    CapitalRemittance.update_all("folio_call_amount_cents=call_amount_cents,folio_collected_amount_cents=collected_amount_cents, folio_committed_amount_cents=committed_amount_cents")

    CapitalRemittancePayment.update_all("folio_amount_cents=amount_cents")
    CapitalDistributionPayment.update_all("folio_amount_cents=amount_cents")
    AccountEntry.update_all("folio_amount_cents=amount_cents")
  end
end
