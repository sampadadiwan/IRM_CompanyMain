class InvestorKyc < ApplicationRecord # rubocop:disable Metrics/ClassLength
  STANDARD_COLUMNS = { "Investor" => "investor_name",
                       "Investing Entity" => "full_name",
                       "Type" => "kyc_type",
                       "Completed" => "completed_by_investor",
                       "Kyc Verified" => "verified",
                       "Expired" => "expired" }.freeze

  INVESTOR_TAB_STANDARD_COLUMNS = STANDARD_COLUMNS.except("Investor").freeze

  INVESTOR_STANDARD_COLUMNS = { "Entity" => "entity_name",
                                "Investing Entity" => "full_name",
                                "Type" => "kyc_type",
                                "Completed" => "completed_by_investor",
                                "Kyc Verified" => "verified",
                                "Expired" => "expired" }.freeze

  SEBI_INVESTOR_CATEGORIES = %i[Internal Domestic Foreign Other].freeze

  SEBI_INVESTOR_SUB_CATEGORIES_MAPPING = {
    Internal: ["Sponsor", "Manager", "Directors/Partners/Employees of Sponsor", "Directors/Partners/Employees of Manager", "Employee Benefit Trust of Manager"],
    Domestic: ["Banks", "NBFCs", "Insurance Companies", "Pension Funds", "Provident Funds", "AIFs", "Other Corporates", "Resident Individuals", "Non-Corporate (other than Trusts)", "Trusts"],
    Foreign: ["FPIs", "FVCIs", "NRIs", "Foreign Others"],
    Other: ["Domestic Developmental Agencies/Government Agencies", "Others"]
  }.freeze
  # Reporting fields as per regulatory environment
  REPORTING_FIELDS = {
    sebi: {
      sebi_investor_category: { field_type: "Select",
                                meta_data: ",#{SEBI_INVESTOR_CATEGORIES.join(',')}",
                                label: "Investor Category",
                                js_events: "change->form-custom-fields#investor_category_changed" },
      sebi_investor_sub_category: { field_type: "Select",
                                    meta_data: SEBI_INVESTOR_SUB_CATEGORIES_MAPPING.values.flatten.join(","),
                                    label: "Investor Sub Category" }
    }
  }.freeze

  # Make all models searchable
  update_index('investor_kyc') { self if index_record?(InvestorKycIndex) }
  include WithCustomField
  include Trackable.new
  include WithFolder
  include ForInvestor
  include RansackerAmounts.new(fields: %w[collected_amount committed_amount call_amount distribution_amount])
  include WithFriendlyId
  include WithIncomingEmail
  include InvestorKycConcern
  include WithDocQuestions
  include WithSupportAgent

  belongs_to :investor
  belongs_to :entity
  # These are the capital_commitments that are linked to this KYC
  has_many :capital_commitments

  has_many :funds, through: :capital_commitments
  has_many :capital_remittances, through: :capital_commitments
  has_many :capital_remittance_payments, through: :capital_commitments
  has_many :capital_distribution_payments, through: :capital_commitments
  has_many :account_entries, through: :capital_commitments
  has_many :fund_units, through: :capital_commitments

  # These are the expression_of_interests that are linked to this KYC
  has_many :expression_of_interests

  has_many :noticed_events, as: :record, dependent: :destroy, class_name: "Noticed::Event"

  has_many :aml_reports, dependent: :destroy
  has_many :kyc_datas, dependent: :destroy

  scope :uncalled, -> { where('committed_amount_cents > call_amount_cents') }
  scope :due, -> { where('committed_amount_cents > collected_amount_cents') }
  scope :agreement_uncalled, -> { where('agreement_committed_amount_cents > call_amount_cents') }
  scope :agreement_overcalled, -> { where('agreement_committed_amount_cents <= call_amount_cents') }

  scope :verified, -> { where(verified: true) }
  scope :completed, -> { where(completed_by_investor: true) }
  scope :not_completed, -> { where(completed_by_investor: false) }
  scope :unverified, -> { where(verified: false) }
  scope :expired, -> { where(expiry_date: ..Time.zone.today) }
  scope :not_expired, -> { where('expiry_date IS NULL OR expiry_date >= ?', Time.zone.today) }

  scope :for_investor, lambda { |user|
    joins(:investor).where('investors.investor_entity_id': user.entity_id).joins(entity: :investor_accesses).merge(InvestorAccess.approved_for_user(user))
  }

  # Do not call this with a user who is not an investor_advisor
  scope :for_investor_advisor, lambda { |user, across_all_entities: false|
    # We cant show them all the KYCs, only the ones for the funds they have been permissioned
    fund_ids = Fund.for_investor(user, across_all_entities:).distinct.pluck(:id)

    if across_all_entities && user.has_cached_role?(:investor_advisor)
      joins(investor: :investor_accesses, capital_commitments: :fund)
        .where(funds: { id: fund_ids })
        .merge(InvestorAccess.approved_for_user(user, across_all_entities:)).distinct
    else
      # Give access to all the KYCs for the investor, where he has investor_accesses approved
      # And the investor belongs to the same investor_entity as the user
      # and the fund is one of the funds they have been permissioned
      joins(:investor, capital_commitments: :fund)
        .where('investors.investor_entity_id=? and funds.id in (?)', user.entity_id, fund_ids)
        .joins(entity: :investor_accesses).merge(InvestorAccess.approved_for_user(user)).distinct
    end
  }

  enum :kyc_type, { individual: "Individual", non_individual: "Non Individual" }

  include FileUploader::Attachment(:signature)

  attr_accessor :phone

  belongs_to :verified_by, class_name: "User", optional: true

  validates :kyc_type, :address, :full_name, :birth_date, :PAN, :bank_name, :bank_branch, :bank_account_type, :bank_account_number, :ifsc_code, presence: true

  validates :PAN, length: { maximum: 15 }
  validates :bank_account_number, :bank_branch, :bank_account_type, length: { maximum: 40 }
  validates :ifsc_code, :agreement_unit_type, length: { maximum: 20 }
  validates :full_name, length: { maximum: 255 }
  normalizes :full_name, with: ->(full_name) { full_name.strip.squeeze(" ") }
  validates :kyc_type, length: { maximum: 15 }
  validates :bank_name, length: { maximum: 100 }
  validates :phone, length: { is: 10 }, allow_blank: true

  validate :birth_date_cannot_be_in_the_future
  def birth_date_cannot_be_in_the_future
    errors.add(:birth_date, "can't be in the future") if birth_date.present? && birth_date > Date.current
  end

  validate :sebi_investor_sub_category_hierarchy

  def sebi_investor_sub_category_hierarchy
    json_fields["sebi_investor_category"] = json_fields["sebi_investor_category"]&.strip&.titleize
    json_fields["sebi_investor_sub_category"] = json_fields["sebi_investor_sub_category"]&.strip

    # Rule: category must exist if sub-category exists
    if json_fields["sebi_investor_sub_category"].present? && json_fields["sebi_investor_category"].blank?
      errors.add(:sebi_investor_category, "should be present to enter investor sub-category")
      return
    end

    # If category exists, validate it
    if json_fields["sebi_investor_category"].present?
      allowed_categories = SEBI_INVESTOR_CATEGORIES.map(&:to_s)
      unless allowed_categories.include?(json_fields["sebi_investor_category"])
        errors.add(:sebi_investor_category, "should be one of #{allowed_categories.join(', ')}")
        return
      end

      # Validate sub-category if present
      if json_fields["sebi_investor_sub_category"].present?
        allowed_sub_categories = SEBI_INVESTOR_SUB_CATEGORIES_MAPPING[json_fields["sebi_investor_category"].to_sym] || []
        errors.add(:sebi_investor_sub_category, "should be one of #{allowed_sub_categories.join(', ')}") unless allowed_sub_categories.include?(json_fields["sebi_investor_sub_category"])
      end
    end
  end

  # Customize form
  serialize :pan_verification_response, type: Hash
  serialize :bank_verification_response, type: Hash

  # Note this rollups work only where Fund and Entity currency are the same.
  monetize :committed_amount_cents, :collected_amount_cents, :agreement_committed_amount_cents,
           :call_amount_cents, :distribution_amount_cents, :uncalled_amount_cents, :other_fee_cents,
           with_currency: ->(i) { i.entity.currency }

  # Should be called only from SendKycFormJob
  # If not this leads to bugs where the InvestorKycNotification cannot be created when the kyc_type changes
  def send_kyc_form(reminder: false, custom_notification_id: nil)
    if send_kyc_form_to_user || reminder
      email_method = :notify_kyc_required
      msg = "Kindly update your KYC details for #{entity.name} by clicking on the button below"

      if reminder
        email_method = :kyc_required_reminder
        msg = "Reminder to kindly update your KYC details for #{entity.name} by clicking on the button below."
      end

      # Send notification to all the users who have access to this KYC
      notification_users.each do |user|
        InvestorKycNotifier.with(record: self, entity_id:, email_method:, msg:, user_id: user.id, custom_notification_id:).deliver_later(user)
      end

      # Ensure the flag is set to false after sending the KYC form
      # rubocop:disable Rails/SkipsModelValidations
      if reminder
        update_columns(reminder_sent: true, reminder_sent_date: Time.zone.now, send_kyc_form_to_user: false)
      else
        update_column(:send_kyc_form_to_user, false)
      end
      # rubocop:enable Rails/SkipsModelValidations
    end
  end

  def notification_users
    investor.notification_users.select do |user|
      # Check if the user has access to this KYC
      # For investor advisors, check if they have access to the kyc across all the entities they are advisors for
      across_all_entities = user.has_cached_role?(:investor_advisor)
      Rails.logger.debug { "Checking user: #{user.id} for KYC: #{id} across_all_entities: #{across_all_entities}" }
      InvestorKycPolicy.new(user, self).show?(across_all_entities:)
    end
  end

  def pan_card
    documents.where(owner_tag: "PAN").last&.file
  end

  def updated_notification(msg: nil)
    msg ||= "KYC updated for #{full_name}"
    entity.employees.active.each do |user|
      if user.enable_kycs && !user.investor_advisor?
        InvestorKycNotifier.with(record: self, entity_id:, email_method: "notify_kyc_updated", msg:, user_id: user.id).deliver_later(user)
      else
        Rails.logger.debug { "Not sending KYC updated notification to user #{user.id} as they do not have enable_kycs permission or are an investor_advisor" }
      end
    end
  end

  before_save :set_investor_name
  def set_investor_name
    self.type = type_from_kyc_type
    Rails.logger.debug { "self.type: #{type}" }
    self.investor_name = investor.investor_name
  end

  def due_amount
    call_amount - collected_amount + other_fee
  end

  def uncalled_amount
    custom_committed_amount - call_amount
  end

  def type_from_kyc_type
    "#{kyc_type.titleize.delete(' ')}Kyc" if kyc_type.present?
  end

  def custom_committed_amount
    agreement_committed_amount_cents.positive? ? agreement_committed_amount : committed_amount
  end

  def folder_path
    if full_name.present?
      "#{investor.folder_path}/KYC-#{id_or_random_int}/#{full_name.delete('/')}"
    else
      "#{investor.folder_path}/KYC-#{id_or_random_int}/#{investor.investor_name.delete('/')}"
    end
  end

  def investor_signatories
    esign_emails&.split(",")&.map(&:strip)
  end

  def to_s
    full_name || investor_name
  end

  def enable_kyc
    investor.investor_entity.permissions.set(:enable_kycs)
    investor.investor_entity.save
  end

  def generate_aml_report(user_id)
    GenerateAmlReportJob.perform_later(id, user_id) if id.present? && full_name.present?
  end

  def full_name_has_changed?
    full_name.present? && saved_change_to_full_name?
  end

  def expired?
    expiry_date ? expiry_date < Time.zone.today : false
  end

  def assign_kyc_data(kyc_data, user)
    self.full_name = kyc_data.full_name
    self.address = kyc_data.perm_address
    self.corr_address = kyc_data.corr_address
    # add below images as attached documents
    kyc_data.get_image_data.each do |image_data|
      imgtype = image_data['image_type']
      file_name = "#{kyc_data.source.upcase}Data-#{id}-#{full_name.delete('/')}-#{imgtype}.png"
      file_path = "tmp/#{file_name}"
      if imgtype.casecmp?("pan")
        Rails.logger.debug { "Uploading new image - #{file_name}" }
        Rails.root.join(file_path).binwrite(Base64.decode64(image_data['data']))
        Document.create!(name: "Upload Pan Card", entity_id:, owner: self, user:, file: File.open(file_path, "rb"))
      end

      FileUtils.rm_f(file_path)
    rescue StandardError => e # caught as kyc can have improper base64 data
      Rails.logger.error { "Error while uploading file #{file_name} #{e.message}" }
    end
  end

  def remove_images
    # remove attached image documents from kyc data
  end

  def commitment_pending
    committed_amount - collected_amount
  end

  def total_fund_units
    # Find all the committments this kyc is tied to
    entity.fund_units.joins(capital_commitment: :investor_kyc).where("investor_kycs.id=?", id).sum(:quantity)
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[PAN full_name investor_name kyc_type address bank_name bank_branch bank_account_type bank_account_number ifsc_code birth_date verified completed_by_investor expiry_date collected_amount committed_amount call_amount distribution_amount docs_completed json_fields created_at aml_status].sort
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[capital_commitments investor funds]
  end

  def self.ransackable_scopes(_auth_object = nil)
    %i[verified expired not_expired due]
  end

  def face_value_for_redemption(start_date: nil, end_date: nil)
    cdp = capital_distribution_payments
    cdp = cdp.where(payment_date: start_date..) if start_date.present?
    cdp = cdp.where(payment_date: ..end_date) if end_date.present?
    Money.new(cdp.sum(:cost_of_investment_cents), entity.currency)
  end

  def self.cleanup_zeros(ent)
    ent.investor_kycs.each do |kyc|
      kyc.properties.each do |name, val|
        kyc.properties.delete(name) if val == "0"
      end
      kyc.save(validate: false)
    end
    nil
  end

  # In some cases the agreement_unit_type is specified in the KYC, before a commitment is created.
  # And we need the corresponding fund unit setting (for document generation), from any fund in the entity. This is for Angel Funds only. For other funds, the agreement_unit_type is not used.
  def agreement_unit_setting
    entity.funds.first.fund_unit_settings.where(name: agreement_unit_type).first
  end

  def doc_questions
    entity.doc_questions.where(owner: entity, for_class: "InvestorKyc")
  end

  def ckyc_data
    kyc_datas.ckyc.where(PAN: self.PAN).last
  end

  def kra_data
    kyc_datas.kra.where(PAN: self.PAN).last
  end

  def kyc_data_fields_populated
    full_name.present? || address.present? || corr_address.present?
  end
end
