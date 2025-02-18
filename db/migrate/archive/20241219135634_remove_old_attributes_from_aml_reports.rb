class RemoveOldAttributesFromAmlReports < ActiveRecord::Migration[7.2]
  def change
    if column_exists?(:aml_reports, :approved)
      remove_column :aml_reports, :approved
    end
    if column_exists?(:aml_reports, :approved_on)
      remove_column :aml_reports, :approved_on
    end
    if column_exists?(:aml_reports, :approved_by_id)
      remove_column :aml_reports, :approved_by_id
    end
  end
end
