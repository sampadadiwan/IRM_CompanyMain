class AddFeeFormulasToCapitalCall < ActiveRecord::Migration[7.1]
  def change
    add_column :call_fees, :formula, :boolean, default: false
  end
end
