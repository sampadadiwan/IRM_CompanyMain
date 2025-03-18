class AddPanToAmlReports < ActiveRecord::Migration[7.2]
  def change
    unless column_exists?(:aml_reports, :PAN)
      add_column :aml_reports, :PAN, :string
    end
  end
end
