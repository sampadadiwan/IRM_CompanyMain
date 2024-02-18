class AddDueAmountToInvestorKyc < ActiveRecord::Migration[7.1]
  def change
    add_column :investor_kycs, :due_amount_cents, :decimal, precision: 20, scale: 2, default: 0.0
    add_column :investor_kycs, :uncalled_amount_cents, :decimal, precision: 20, scale: 2, default: 0.0
    add_column :investor_kycs, :agreement_committed_amount_cents, :decimal, precision: 20, scale: 2, default: 0.0

    InvestorKyc.where("json_fields->>\"$.committed_amount\" > ?", 0).each do |kyc|
      kyc.update_column(:agreement_committed_amount_cents, kyc.json_fields["committed_amount"].to_f * 100)
      kyc.json_fields.delete("committed_amount")
      kyc.update_column(:json_fields, kyc.json_fields)
    end
  end
end
