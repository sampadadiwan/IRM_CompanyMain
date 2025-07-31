class AddTemplateToReport < ActiveRecord::Migration[8.0]
  def change
    add_column :reports, :template, :json
    add_column :reports, :template_xls_data, :text
  end
end
