class AddSlugToDeal < ActiveRecord::Migration[7.1]
  def change
    add_column :deals, :slug, :string
    add_index :deals, :slug, unique: true
    add_column :funds, :slug, :string
    add_index :funds, :slug, unique: true
    add_column :capital_commitments, :slug, :string
    add_index :capital_commitments, :slug, unique: true
    add_column :investor_kycs, :slug, :string
    add_index :investor_kycs, :slug, unique: true
    add_column :deal_investors, :slug, :string
    add_index :deal_investors, :slug, unique: true
    add_column :investors, :slug, :string
    add_index :investors, :slug, unique: true
  end
end
