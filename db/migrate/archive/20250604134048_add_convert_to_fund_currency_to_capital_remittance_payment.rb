class AddConvertToFundCurrencyToCapitalRemittancePayment < ActiveRecord::Migration[8.0]
  def change
    unless column_exists?(:capital_remittance_payments, :convert_to_fund_currency)
      add_column :capital_remittance_payments, :convert_to_fund_currency, :boolean, default: true, null: false
    end
  end
end
