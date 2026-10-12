# The investing entity (KYC) an evergreen order is for. A folio opened by the order takes it, so
# pay-after folios opened at confirm get the KYC chosen at order time (evergreen-folio-soa ①).
class AddInvestorKycToDealingOrders < ActiveRecord::Migration[8.1]
  def change
    add_reference :dealing_orders, :investor_kyc, null: true, foreign_key: true, index: true
  end
end
