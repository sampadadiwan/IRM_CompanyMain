class AddEntryTypeToRatioFormulas < ActiveRecord::Migration[8.1]
  def change
    unless column_exists?(:ratio_formulas, :entry_type)
      add_column :ratio_formulas, :entry_type, :string, limit: 60
    end
    unless column_exists?(:ratio_formulas, :cumulative)
      add_column :ratio_formulas, :cumulative, :boolean, default: false
    end
    unless column_exists?(:ratio_formulas, :parent_type)
      add_column :ratio_formulas, :parent_type, :string
    end
  end
end
