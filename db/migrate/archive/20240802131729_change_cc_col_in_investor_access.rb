class ChangeCcColInInvestorAccess < ActiveRecord::Migration[7.1]
  def change
    # Change the column type from string to text
    change_column :investor_accesses, :cc, :text
  end
end
