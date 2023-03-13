class AddDateToExchangeRate < ActiveRecord::Migration[7.0]
  def change
    add_column :exchange_rates, :as_of, :date
  end

  CapitalCommitment.all.each do |cc|
    cc.folio_currency = cc.fund.currency
    cc.folio_committed_amount_cents = cc.committed_amount_cents
    cc.save
  end

  CapitalRemittance.update_all("folio_call_amount_cents=call_amount_cents, folio_collected_amount_cents=collected_amount_cents, folio_committed_amount_cents=committed_amount_cents")

  CapitalRemittancePayment.update_all("folio_amount_cents=amount_cents")
  CapitalDistributionPayment.update_all("folio_amount_cents=amount_cents")
  AccountEntry.update_all("folio_amount_cents=amount_cents")

end
