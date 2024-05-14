class AddAttributesToDealInvestor < ActiveRecord::Migration[7.1]
  def change
    add_column :deal_investors, :total_amount_cents, :decimal, precision: 20, scale: 2
    add_column :deal_investors, :tags, :string
    add_column :deal_investors, :deal_lead, :string
    add_column :deal_investors, :source, :string
    add_column :deal_investors, :introduced_by, :string
    add_column :deal_investors, :notes, :text
  end
end