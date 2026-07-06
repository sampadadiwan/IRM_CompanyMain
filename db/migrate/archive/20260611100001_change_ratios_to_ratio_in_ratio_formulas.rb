class ChangeRatiosToRatioInRatioFormulas < ActiveRecord::Migration[8.1]
  def up
    # Migrate JSON array column to a single string column.
    # Extract the first element of the existing array; most rows have exactly one value.
    add_column :ratio_formulas, :ratio, :string

    execute <<~SQL
      UPDATE ratio_formulas
      SET ratio = JSON_UNQUOTE(JSON_EXTRACT(ratios, '$[0]'))
      WHERE ratios IS NOT NULL AND JSON_LENGTH(ratios) > 0
    SQL

    remove_column :ratio_formulas, :ratios
  end

  def down
    add_column :ratio_formulas, :ratios, :json

    execute <<~SQL
      UPDATE ratio_formulas
      SET ratios = JSON_ARRAY(ratio)
      WHERE ratio IS NOT NULL
    SQL

    remove_column :ratio_formulas, :ratio
  end
end
