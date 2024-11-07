class AddModelToReports < ActiveRecord::Migration[7.1]
  def change
    add_column :reports, :model, :string
    Report.find_each do |report|
      path = ActiveSupport::HashWithIndifferentAccess.new(Report.reports_for)[report.category]
      next unless path

      controller_name = path.split('?').first.delete_prefix('/')
      model_name = controller_name.singularize.camelize

      report.update_column(:model, model_name)
    end
  end
end
