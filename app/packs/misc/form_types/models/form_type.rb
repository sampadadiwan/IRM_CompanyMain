class FormType < ApplicationRecord
  include WithGridViewPreferences
  belongs_to :entity

  validates :name, presence: true
  validates :name, length: { maximum: 255 }
  validates :tag, length: { maximum: 50 }

  has_many :form_custom_fields, -> { order(position: :asc) }, inverse_of: :form_type, dependent: :destroy
  accepts_nested_attributes_for :form_custom_fields, reject_if: :all_blank, allow_destroy: true

  # Sometimes after we import data, we have custom fields which get imported
  # But there exists no custom form fields for the import - hence we can see it but not edit it.
  # This automatically sets up the custom form fields, given that custom fields have been imported into the record
  def self.save_cf_from_import(custom_field_headers, import_upload, form_type_id = nil)
    newly_created_cf = []
    if custom_field_headers.present?
      # Create the form type
      import_upload.form_type_names.each do |name|
        # We could get the rows imported from import_upload. However for KYCs, we could import Individual and Non Individual in the same file. So we need to create the appropriate custom fields for each form type
        imported_row_count = name.constantize.where(entity_id: import_upload.entity_id, import_upload_id: import_upload.id).count
        next unless imported_row_count.positive?

        # Find or create the form type
        if form_type_id.present?
          form_type = FormType.find(form_type_id)
        else
          # find the last one with the name
          form_type = FormType.where(name:, entity_id: import_upload.entity_id).last
          # or create it
          form_type ||= FormType.create(name:, entity_id: import_upload.entity_id)
        end

        custom_field_headers.each do |cfh|
          # Create the custom form fields for the form type
          cust_field_key = cfh
          name = FormCustomField.to_name(cust_field_key)
          next if form_type.form_custom_fields.exists?(name:)

          form_type.form_custom_fields.create(name:, field_type: "TextField", label: cust_field_key)
          newly_created_cf << cust_field_key
        end
      end
    end
    newly_created_cf
  end

  def dup_cf_names?
    uniq_fcfs = form_custom_fields.uniq(&:name)
    if uniq_fcfs.count == form_custom_fields.count
      false
    else
      dups = form_custom_fields - uniq_fcfs
      dups.each do |dup|
        dup.errors.add(:name, "cannot have duplicate names")
      end
      true
    end
  end

  def deep_clone(eid)
    # Check if entity already has this form type
    ftd = dup
    ftd.entity_id = eid
    form_custom_fields.order(position: :asc).each do |fcf|
      ftd.form_custom_fields << fcf.dup
    end
    ftd.save!

    ftd
  end

  # Ensure that all the models of this entity have the form type id set
  after_save :update_models
  def update_models
    cn = name.constantize
    cn.where(entity_id:, form_type_id: nil).update_all(form_type_id: id)
    FormTypeJob.perform_later(id)
  end

  # Ensure that all the custom fields defined in the form type are present in the json_fields of the models
  # Called by FormTypeJob
  def ensure_json_fields
    cn = name.constantize
    cn.where(entity_id:).find_each(&:ensure_json_fields)
  end

  def model
    name.constantize
  end
end
