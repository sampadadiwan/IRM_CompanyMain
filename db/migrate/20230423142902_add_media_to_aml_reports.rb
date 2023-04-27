class AddMediaToAmlReports < ActiveRecord::Migration[7.0]
  def change
    add_column :aml_reports, :media, :json
  end
end
