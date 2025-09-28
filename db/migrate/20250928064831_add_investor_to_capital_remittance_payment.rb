class AddInvestorToCapitalRemittancePayment < ActiveRecord::Migration[8.0]


  def up
    unless column_exists?(:capital_remittance_payments, :investor_id)
      add_reference :capital_remittance_payments, :investor, null: true, foreign_key: true

      # Bulk SQL update for efficiency (MySQL-compatible syntax)
      execute <<-SQL.squish
        UPDATE capital_remittance_payments crp
        INNER JOIN capital_remittances cr ON crp.capital_remittance_id = cr.id
        SET crp.investor_id = cr.investor_id
      SQL

      # Add NOT NULL constraint after populating existing records
      change_column_null :capital_remittance_payments, :investor_id, false
    end
  end
  def down
      remove_reference :capital_remittance_payments, :investor, foreign_key: true
  end
end
