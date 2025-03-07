class ChangeExtractToHaveNullSection < ActiveRecord::Migration[7.2]
  def change
    change_column_null :portfolio_report_extracts, :portfolio_report_section_id, true
  end
end
