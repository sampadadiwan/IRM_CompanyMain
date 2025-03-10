class AddCustomNameToAmlReports < ActiveRecord::Migration[7.2]
  def change
    unless column_exists?(:aml_reports, :custom_name)
      add_column :aml_reports, :custom_name, :string
    end
    unless column_exists?(:aml_reports, :request_id)
      add_column :aml_reports, :request_id, :string
    end
    unless column_exists?(:aml_reports, :birth_date)
      add_column :aml_reports, :birth_date, :datetime
    end

    migrate_old_aml_reports
  end
  
  def migrate_old_aml_reports
    AmlReport.find_each do |aml_report|
      Rails.logger.debug "Updating AML Report #{aml_report.id}"
      aml_report.birth_date = aml_report.investor_kyc.birth_date if aml_report.birth_date.blank?
      if aml_report.request_id.blank? && aml_report.response_data.present?
        last_response = aml_report.response_data[aml_report.response_data.keys.last]
        if last_response.instance_of?(Hash)
          aml_report.request_id = last_response["request_id"]
        elsif last_response.instance_of?(Array)
          aml_report.request_id = last_response.first["request_id"]
        end
      end
      aml_report.save!
    end
  end

end