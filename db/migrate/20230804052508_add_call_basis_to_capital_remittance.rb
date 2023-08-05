class AddCallBasisToCapitalRemittance < ActiveRecord::Migration[7.0]
  def change
    add_column :capital_calls, :call_basis, :string, limit: 40
    add_column :capital_calls, :amount_to_be_called_cents, :decimal, precision: 20, scale: 2, default: 0.0
    add_column :capital_remittances, :computed_amount_cents, :decimal, precision: 20, scale: 2, default: 0.0
  end

  # CapitalCall.update_all(call_basis: "Percentage of Commitment")
end
