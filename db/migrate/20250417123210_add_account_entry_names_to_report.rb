class AddAccountEntryNamesToReport < ActiveRecord::Migration[8.0]
  def change
    add_column :reports, :metadata, :text
    add_column :account_entries, :parent_name, :string
    add_column :account_entries, :commitment_name, :string

    # AccountEntry.includes(:fund_formula).all.each do |entry|
    #   entry.setup_defaults
    #   entry.name = entry.fund_formula.name 
    #   entry.entry_type = entry.fund_formula.entry_type   
    #   entry.save(validate: false)
    # end
  end
end
