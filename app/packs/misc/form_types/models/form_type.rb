class FormType < ApplicationRecord
  belongs_to :entity

  has_many :form_custom_fields, -> { order(position: :asc) }, inverse_of: :form_type, dependent: :destroy
  accepts_nested_attributes_for :form_custom_fields, reject_if: :all_blank, allow_destroy: true

  # Sometimes after we import data, we have custom fields which get imported
  # But there exists no custom form fields for the import - hence we can see it but not edit it.
  # This automatically sets up the custom form fields, given that custom fields have been imported into the record
  def self.save_cf_from_import(custom_field_headers, import_upload)

    if custom_field_headers.present?
      # Create the form type
      name = import_upload.import_type
      # We have a special case for InvestorKyc - there are 2 type IndividualKyc and NonIndividualKyc
      name = (name == "InvestorKyc") ?  import_upload.entity.investor_kycs.last&.class&.name : name

      # Find or create the form type
      form_type = FormType.find_or_create_by(name:, entity_id: import_upload.entity_id)

      custom_field_headers.each do |cfh|
        # Create the custom form fields for the form type
        cust_field_key = cfh
        form_type.form_custom_fields.create(name: cust_field_key, field_type: "text_field") unless form_type.form_custom_fields.exists?(name: cust_field_key)
      end
    end
    
  end
end
