class FormType < ApplicationRecord
  include WithGridViewPreferences

  # These models can have multiple form types attached to them, so when we upload the data we cannot auto create the form types
  MULTIPLE_FORM_TYPES_ALLOWED = %w[CapitalCommitment InvestorKyc IndividualKyc NonIndividualKyc Offer Interest SupportAgent].freeze

  belongs_to :entity

  validates :name, :tag, presence: true
  validates :name, length: { maximum: 255 }
  # Only enforce uniqueness if the form type is not in the multiple allowed list
  validates :name, uniqueness: { scope: :entity_id }, unless: ->(record) { MULTIPLE_FORM_TYPES_ALLOWED.include?(record.name) }
  validates :tag, length: { maximum: 50 }
  validates :tag, uniqueness: { scope: %i[entity_id name] }, allow_blank: true

  scope :with_deleted, -> { unscope(where: :deleted_at) }

  has_many :form_custom_fields, -> { order(position: :asc) }, inverse_of: :form_type, dependent: :destroy
  accepts_nested_attributes_for :form_custom_fields, reject_if: :all_blank, allow_destroy: true

  attr_accessor :reg_env

  before_save :add_regulatory_custom_fields, if: -> { reg_env.present? && FormCustomField::REGULATORY_FIELD_MODELS.include?(name) }

  # Add the regulatory fields to the form type
  def add_regulatory_custom_fields
    # Skip if the form type is not one of the regulatory models
    return if FormCustomField::REGULATORY_FIELD_MODELS.exclude?(name)

    AddRegulatoryCustomFieldsService.new.add_custom_fields_to_form(self)
  end

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
    # We do not enforce the json_fields via the FormTypeJob anymore, its not required.
    # FormTypeJob.perform_later(id) unless self.name == "AccountEntry" # Dont run for AccountEntry as it has too many records
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

  # Returns sorted integer list of extra step values (4–9) that have at least one visible, non-regulatory field.
  # Queries by enum name strings so behavior is consistent across Rails versions — pluck(:step) returns
  # enum name strings ("four", "five"...) in Rails 7.1+ rather than raw integers, so we normalise
  # the result back to integers before sorting to avoid alphabetical ordering ("eight" < "five" < "four"...).
  def extra_step_numbers
    extra_names = FormCustomField.steps.filter_map { |k, v| k if FormCustomField::EXTRA_STEP_RANGE.include?(v) }
    form_custom_fields
      .not_regulatory
      .visible
      .where(step: extra_names)
      .pluck(:step)
      .map { |s| s.is_a?(Integer) ? s : FormCustomField.steps[s.to_s] }
      .uniq
      .sort
  end

  # Strip blank values so saving the form with empty label fields doesn't store empty strings in JSON.
  def step_labels=(val)
    write_attribute(:step_labels, val.present? ? val.reject { |_, v| v.blank? }.presence : nil)
  end

  # Human-readable label for a given step integer (4–9).
  # Falls back to "Step N" when no label is configured in step_labels (column may be NULL in MySQL).
  def label_for_step(step_num)
    (step_labels.presence || {}).fetch(step_num.to_s, "Step #{step_num}")
  end

  def to_s
    if tag.blank?
      name
    else
      "#{name} - #{tag}"
    end
  end
end
