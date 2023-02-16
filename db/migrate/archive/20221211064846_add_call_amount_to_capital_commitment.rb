class AddCallAmountToCapitalCommitment < ActiveRecord::Migration[7.0]
  def change
    add_column :capital_commitments, :call_amount_cents, :decimal, precision: 20, scale: 2, default: "0.0"
    add_column :capital_commitments, :distribution_amount_cents, :decimal, precision: 20, scale: 2, default: "0.0"
    add_reference :capital_distribution_payments, :capital_commitment, null: true, foreign_key: true

    CapitalDistributionPayment.all.each do |cdp|
      cdp.capital_commitment_id = cdp.fund.capital_commitments.where(investor_id: cdp.investor_id, folio_id: cdp.folio_id).first&.id
      cdp.save
    end
  end
end
