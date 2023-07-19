class AddApprovedOnToAmlReports < ActiveRecord::Migration[7.0]
  def change
    add_column :aml_reports, :approved_on, :datetime
  end
end
