class AddCustomFieldForInvestorKyc < ActiveRecord::Migration[8.0]
  def up
    FormType.where(name: ["InvestorKyc", "IndividualKyc", "NonIndividualKyc"]).find_each do |form_type|
      form_type.form_custom_fields.create(name: "Upload Cancelled Cheque / Bank Statement", label: "Upload Cancelled Cheque / Bank Statement", field_type: "file", required: false, step: "two", meta_data: "Cheque")
      form_type.form_custom_fields.create(name: "residency", label: "Residency", field_type: "select", required: false, step: "three", meta_data: "Domestic,Foreign")


      InvestorKyc.where(form_type_id: form_type.id).find_each do |investor_kyc|
        investor_kyc.custom_fields["residency"] = investor_kyc.residency&.humanize
        investor_kyc.update_column(:json_fields, investor_kyc.custom_fields)
      end
    end
  end

  def down
    FormType.where(name: ["InvestorKyc", "IndividualKyc", "NonIndividualKyc"]).find_each do |form_type|
      form_type.form_custom_fields.where(label: "Upload Cancelled Cheque / Bank Statement").destroy_all
      form_type.form_custom_fields.where(name: "residency").destroy_all
    end

  end
end
