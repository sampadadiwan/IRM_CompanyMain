class AllowBlankinCustomFieldSelect < ActiveRecord::Migration[8.0]
  def change
    FormCustomField.where(name:"investor_category").each do |fcf|
      if fcf.meta_data == "Internal,Domestic,Foreign,Other"
        Rails.logger.info "Updating custom field #{fcf.name} for form type #{fcf.form_type.id} to allow blank values"
        fcf.meta_data = ",Internal,Domestic,Foreign,Other"
        fcf.save!
      end
    end

  end
end
