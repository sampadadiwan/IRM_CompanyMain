class AddLabelToRatioFormulas < ActiveRecord::Migration[8.1]
  def change
    unless column_exists?(:ratio_formulas, :label)
      add_column :ratio_formulas, :label, :string, limit: 30
    end
  end
end
