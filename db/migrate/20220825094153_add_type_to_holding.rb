class AddTypeToHolding < ActiveRecord::Migration[7.0]
  def change
    add_column :holdings, :option_type, :string, limit: 12
    add_column :holdings, :option_dilutes, :boolean, default: true
  end
end
