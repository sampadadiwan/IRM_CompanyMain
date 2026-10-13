# What one fund's investors hold, when it differs from the entity's wording: "unit" or "share".
# Blank = the entity's / locale's word (Units). Wording only — never changes any figure.
class AddUnitTermToEvergreenFundSettings < ActiveRecord::Migration[8.1]
  def change
    add_column :evergreen_fund_settings, :unit_term, :string, limit: 10
  end
end
