class AddRequestDataToAmlReport < ActiveRecord::Migration[7.2]
  def change
    unless column_exists?(:aml_reports, :request_data)
      add_column :aml_reports, :request_data, :json
    end
    if column_exists?(:aml_reports, :response)
      rename_column :aml_reports, :response, :response_data
    end
    if column_exists?(:aml_reports, :types)
      remove_column :aml_reports, :types
    end
    if column_exists?(:aml_reports, :source_notes)
      remove_column :aml_reports, :source_notes
    end
    if column_exists?(:aml_reports, :associates)
      remove_column :aml_reports, :associates
    end
    if column_exists?(:aml_reports, :fields)
      remove_column :aml_reports, :fields
    end
    if column_exists?(:aml_reports, :media)
      remove_column :aml_reports, :media
    end
  end
end
