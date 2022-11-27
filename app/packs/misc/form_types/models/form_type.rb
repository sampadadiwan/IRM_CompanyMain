class FormType < ApplicationRecord
  has_many :form_custom_fields, -> { order(position: :asc) }, inverse_of: :form_type, dependent: :destroy
  accepts_nested_attributes_for :form_custom_fields, reject_if: :all_blank, allow_destroy: true

  # Sometimes after we import data, we have custom fields which get imported
  # But there exists no custom form fields for the import - hence we can see it but not edit it.
  # This automatically sets up the custom form fields, given that custom fields have been imported into the record
  def self.extract_from_db(model)
    if model.properties.present?
      # Create the form type
      form_type = FormType.where(name: model.class.name, entity_id: model.entity_id).first
      form_type ||= FormType.create(name: model.class.name, entity_id: model.entity_id)
      model.properties.each_key do |key|
        # Create the custom form fields
        cust_field_key = key.instance_of?(Symbol) ? key : key.parameterize.underscore
        form_type.form_custom_fields.create(name: cust_field_key, field_type: "text_field") unless form_type.form_custom_fields.exists?(name: cust_field_key)
      end
    end
  end
end
