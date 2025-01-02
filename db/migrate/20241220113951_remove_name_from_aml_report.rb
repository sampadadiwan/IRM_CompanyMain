class RemoveNameFromAmlReport < ActiveRecord::Migration[7.2]
  def change
    if column_exists?(:aml_reports, :name)
      remove_column :aml_reports, :name
    end
  end
end
