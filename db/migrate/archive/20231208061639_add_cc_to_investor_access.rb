class AddCcToInvestorAccess < ActiveRecord::Migration[7.1]
  def change
    add_column :investor_accesses, :cc, :string
  end
end
