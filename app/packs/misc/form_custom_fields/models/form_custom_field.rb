class FormCustomField < ApplicationRecord
  belongs_to :form_type
  acts_as_list scope: :form_type

  enum :step,  { one: 1, two: 2, three: 3, end: 100 }

  normalizes :name, with: ->(name) { name.strip.titleize.delete(" ").underscore.gsub(/[^0-9A-Za-z_]/, '') }
  validates :name, :show_user_ids, length: { maximum: 100 }
  validates :label, length: { maximum: 254 }
  validates :field_type, length: { maximum: 20 }

  RENDERERS = { Money: "/form_custom_fields/display/money", DateField: "/form_custom_fields/display/date" }.freeze

  scope :writable, -> { where(read_only: false) }

  before_save :set_default_values
  def set_default_values
    self.name = name.strip.downcase
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

  def self.migrate_old_data
    old_data = [[93, "Type of Investor", "InvestorKyc", 47, "Carpediem"],
                [94, "Type of Investor as per SEBI", "InvestorKyc", 47, "Carpediem"],
                [103, "mutual_funds_/_F_Ds", "Valuation", 19, "Sauce.VC"],
                [229, "Individual", "Offer", 762, "Ambit Private Limited"],
                [244, "value_of_stamp_paper_SH4", "Offer", 4, "Demo Startup"],
                [282, "dob_doi`", "InvestorKyc", 844, "SiriusOne"],
                [327, "net sales", "KpiReport", 4, "Demo Startup"],
                [330, "no of orders   net", "KpiReport", 4, "Demo Startup"],
                [331, "net working capital", "KpiReport", 4, "Demo Startup"],
                [332, "total assets", "KpiReport", 4, "Demo Startup"],
                [337, "distributor name", "InvestorKyc", 3103, "Artha"],
                [339, "whether valuation report available?", "Valuation", 69, "Demo Fund"],
                [491, "gein_(global_entity_identification_number)", "NonIndividualKyc", 844, "SiriusOne"],
                [492, "provide_tin_(tax_identification_number)", "NonIndividualKyc", 844, "SiriusOne"],
                [497, "registered_office_address/_place_of_business", "NonIndividualKyc", 844, "SiriusOne"],
                [521, "father's_name", "NonIndividualKyc", 844, "SiriusOne"],
                [522, "spouse's_name", "NonIndividualKyc", 844, "SiriusOne"],
                [530, "provide_aadhar_card/passport_of_controlling_person", "NonIndividualKyc", 844, "SiriusOne"]]

    old_data.each do |row|
      id = row[0]
      old_name = row[1]
      fcf = FormCustomField.find(id)
      fcf.save
      fcf.change_name(old_name)
    end
  end
end
