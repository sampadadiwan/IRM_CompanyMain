class FormCustomField < ApplicationRecord
  HIDDEN_FIELDS = %w[Calculation GridColumns].freeze

  belongs_to :form_type
  acts_as_list scope: :form_type

  enum :step,  { one: 1, two: 2, three: 3, end: 100 }

  # normalizes :name, with: ->(name) { FormCustomField.to_name(name) }
  validates :name, :show_user_ids, length: { maximum: 100 }
  validates :label, length: { maximum: 254 }
  validates :field_type, length: { maximum: 20 }
  validates :reg_env, length: { maximum: 15 }

  validates :name, uniqueness: { scope: :form_type_id }
  validates :name, presence: true

  has_rich_text :info

  REGULATORY_ENVS = %w[SEBI CRISIL IFSC MAS].freeze
  REGULATORY_FIELD_MODELS = %w[IndividualKyc NonIndividualKyc InvestmentInstrument].freeze

  RENDERERS = { Money: "/form_custom_fields/display/money", DateField: "/form_custom_fields/display/date", MultiSelect: "/form_custom_fields/display/multi_select" }.freeze

  scope :writable, -> { where(read_only: false) }
  scope :visible, -> { where.not(field_type: HIDDEN_FIELDS) }
  scope :calculations, -> { where(field_type: "Calculation") }
  # Internal fields are those that are setup by CapHive for SEBI reporting etc. Not changable by the company
  scope :internal, -> { where(internal: true) }
  scope :not_internal, -> { where(internal: false) }
  scope :regulatory, -> { where.not(reg_env: [nil, ""]) }
  scope :not_regulatory, -> { where(reg_env: [nil, ""]) }
  scope :for_env, ->(env) { where(reg_env: env) }

  validate :meta_data_kosher?, if: -> { field_type == "Calculation" }

  def meta_data_kosher?
    errors.add(:meta_data, "You cannot do CRUD operations in meta_data") if meta_data.downcase.match?(SAFE_EVAL_REGEX)
  end

  validate :read_only_and_required, if: -> { read_only && required }
  def read_only_and_required
    errors.add(:read_only, "Read only fields cannot be required")
  end

  validate :condition_on_custom_field, if: -> { condition_on.present? }
  def condition_on_custom_field
    # Only investor.category and investor_kyc.kyc_type standard fields can be used as condition_on
    if (form_type.name == "Investor" && condition_on == "category") ||
       (form_type.name == "InvestorKyc" && condition_on == "kyc_type")
      # Do nothing
    else
      # Check if the field is a custom field, as we can have custom fields only dependent on other custom fields
      parent_field = form_type.form_custom_fields.find { |fcf| fcf.name == condition_on }
      errors.add(:condition_on, "#{name} can be applied only on existing custom fields") if parent_field.nil?
    end
  end

  # This is to ensure that a field cannot be dependent on another field that is itself dependent on another conditional field
  # This is to prevent a chain of dependencies that can lead to complex and unmanageable conditions.
  validate :condition_two_level_max, if: -> { condition_on.present? }
  def condition_two_level_max
    parent_field = form_type.form_custom_fields.find { |fcf| fcf.name == condition_on }
    if parent_field.present? && parent_field.condition_on.present?
      grandparent_field = form_type.form_custom_fields.find { |fcf| fcf.name == parent_field.condition_on }
      errors.add(:condition_on, "#{name} cannot be dependent on a field that is itself dependent on another conditional field (more than two levels)") if grandparent_field.present? && grandparent_field.condition_on.present?
    end
  end

  def initialize(*)
    super
    self.field_type ||= "TextField"
  end

  before_create :set_default_values
  def set_default_values
    self.name = FormCustomField.to_name(name)
    self.label ||= name.humanize
  end

  def renderer
    RENDERERS[field_type.to_sym]
  end

  def show_to_user(user)
    show_user_ids.blank? || show_user_ids.split(",").include?(user.id.to_s)
  end

  def human_label
    label.presence || name.humanize.titleize
  end

  # This is no longer applicable as name cannot be changed on the UI
  # after_commit :change_name_job, on: :update, if: :saved_change_to_name?

  # def change_name_job
  #   FcfNameChangeJob.perform_later(id, previous_changes[:name].first)
  # end

  def change_name(old_name)
    # Loop thru all the records
    klass = form_type.name.constantize
    Rails.logger.debug { "Changing name from #{old_name} to #{name} for #{form_type.name}" }

    klass.where(entity_id: form_type.entity_id).where.not(properties: {}).find_each do |record|
      # Replace the name value with the old name value
      record.properties[name] = record.properties[old_name]
      record.properties.delete(old_name)
      # Save the record without callbacks
      record.update_column(:properties, record.properties)
    end
  end

  def form_class(current_user = nil)
    css_class = "fcf"
    css_class += read_only && current_user&.curr_role == "investor" ? " hidden_form_field" : ""
    if condition_on.present?
      css_class += " conditional #{form_type.name.underscore}_properties_#{condition_on} #{form_type.name.underscore}_#{condition_on}"
      css_class += " #{condition_state}"
    end
    css_class
  end

  def data_attributes
    if condition_on.present?
      "data-match-value='#{condition_params}' data-match-criteria='#{condition_criteria}' data-mandatory='#{required}'"
    else
      "data-mandatory='#{required}'"
    end
  end

  def self.to_name(header)
    header.strip.titleize.squeeze(" ").tr(" ", "_").underscore.gsub(/[^0-9A-Za-z_]/, '').squeeze("_")
  end
end
