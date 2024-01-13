class InvestorKyc < ApplicationRecord
  STANDARD_COLUMN_NAMES = ["Investor", "Full Name", "Type", "Pan", "Pan Verified", "Committed Amount", "Collected Amount", "Bank Verified", "Kyc Verified", "Expired", " "].freeze
  STANDARD_COLUMN_FIELDS = %w[investor_name full_name kyc_type pan pan_verified committed_amount collected_amount bank_verified verified expired dt_actions].freeze

  # Make all models searchable
  update_index('investor_kyc') { self }
  include WithCustomField
  include Trackable
  include WithFolder
  include ForInvestor
  include RansackerAmounts

  belongs_to :investor
  belongs_to :entity
  has_many :capital_commitments
  has_many :funds, through: :capital_commitments
  has_many :capital_remittances, through: :capital_commitments
  has_many :capital_remittance_payments, through: :capital_commitments
  has_many :capital_distribution_payments, through: :capital_commitments
  has_many :account_entries, through: :capital_commitments
  has_many :fund_units, through: :capital_commitments

  has_noticed_notifications

  has_many :aml_reports, dependent: :destroy
  has_many :kyc_datas, dependent: :destroy

  scope :uncalled, -> { where('committed_amount_cents > call_amount_cents') }
  scope :due, -> { where('committed_amount_cents > collected_amount_cents') }
  scope :agreement_uncalled, -> { where('agreement_committed_amount_cents > call_amount_cents') }
  scope :agreement_overcalled, -> { where('agreement_committed_amount_cents <= call_amount_cents') }

  scope :verified, -> { where(verified: true) }
  scope :expired, -> { where(expiry_date: ..Time.zone.today) }
  scope :not_expired, -> { where('expiry_date IS NULL OR expiry_date >= ?', Time.zone.today) }

  enum :kyc_type, { individual: "Individual", non_individual: "Non Individual" }
  enum :residency, { domestic: "Domestic", foreign: "Foreign" }

  include FileUploader::Attachment(:signature)
  include FileUploader::Attachment(:pan_card)

  belongs_to :verified_by, class_name: "User", optional: true

  validates :kyc_type, :address, :full_name, :birth_date, :PAN, :bank_name, :bank_branch, :bank_account_type, :bank_account_number, :ifsc_code, presence: true

  validates :PAN, length: { maximum: 15 }
  validates :bank_account_number, :bank_branch, :bank_account_type, length: { maximum: 40 }
  validates :ifsc_code, length: { maximum: 20 }
  validates :full_name, length: { maximum: 100 }
  normalizes :full_name, with: ->(full_name) { full_name.strip.squeeze(" ") }
  validates :kyc_type, length: { maximum: 15 }
  validates :residency, length: { maximum: 10 }
  validates :bank_name, length: { maximum: 50 }

  validate :birth_date_cannot_be_in_the_future
  def birth_date_cannot_be_in_the_future
    errors.add(:birth_date, "can't be in the future") if birth_date.present? && birth_date > Date.current
  end
  # Customize form
  serialize :pan_verification_response, type: Hash
  serialize :bank_verification_response, type: Hash

  # Note this rollups work only where Fund and Entity currency are the same.
  monetize :committed_amount_cents, :collected_amount_cents, :agreement_committed_amount_cents,
           :call_amount_cents, :distribution_amount_cents, :uncalled_amount_cents,
           with_currency: ->(i) { i.entity.currency }

  after_commit :send_kyc_form, if: :saved_change_to_send_kyc_form_to_user?

  def send_kyc_form(reminder: false)
    if send_kyc_form_to_user || reminder
      email_method = :notify_kyc_required
      msg = "Kindly update your KYC details for #{entity.name} by clicking on the button below"
      if reminder
        email_method = :kyc_required_reminder
        msg = "Reminder to kindly update your KYC details for #{entity.name} by clicking on the button below."
      end
      investor.approved_users.each do |user|
        InvestorKycNotification.with(entity_id:, investor_kyc: self, email_method:, msg:, user_id: user.id).deliver_later(user)
      end
    end
  end

  def updated_notification
    msg = "KYC updated for #{full_name}"
    entity.employees.each do |user|
      InvestorKycNotification.with(entity_id:, investor_kyc: self, email_method: "notify_kyc_updated", msg:, user_id: user.id).deliver_later(user) unless user.investor_advisor?
    end
  end

  before_save :set_investor_name
  def set_investor_name
    self.type = type_from_kyc_type
    Rails.logger.debug { "self.type: #{type}" }
    self.investor_name = investor.investor_name
  end

  def due_amount
    custom_committed_amount - collected_amount
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
    "#{investor.folder_path}/KYC-#{id}/#{full_name.delete('/')}"
  end

  def investor_signatories
    esign_emails&.split(",")&.map(&:strip)
  end

  def to_s
    "#{full_name} - #{self.PAN}"
  end

  def document_list
    if individual?
      docs = entity.entity_setting.individual_kyc_doc_list.split(",").map(&:strip) if entity.entity_setting.individual_kyc_doc_list.present?
    elsif entity.entity_setting.non_individual_kyc_doc_list.present?
      docs = entity.entity_setting.non_individual_kyc_doc_list.split(",").map(&:strip)
    end
    docs + ["Other"] if docs.present?
  end

  # after_commit :send_notification_if_changed, if: :approved

  after_commit :validate_pan_card, unless: :destroyed?
  def validate_pan_card
    VerifyKycPanJob.perform_later(id) if saved_change_to_PAN? || saved_change_to_full_name? || saved_change_to_pan_card_data?
  end

  after_commit :validate_bank, unless: :destroyed?
  def validate_bank
    VerifyKycBankJob.perform_later(id) if saved_change_to_bank_account_number? || saved_change_to_ifsc_code? || saved_change_to_full_name?
  end

  after_save :enable_kyc
  def enable_kyc
    investor.investor_entity.permissions.set(:enable_kycs)
    investor.investor_entity.save
  end
  after_create :generate_aml_report, if: ->(inv_kyc) { inv_kyc.full_name.present? }
  after_update_commit :generate_aml_report, if: :full_name_has_changed?
  def generate_aml_report(user_id = nil)
    AmlReportJob.perform_later(id, user_id) if id.present? && full_name.present?
  end

  def full_name_has_changed?
    full_name.present? && saved_change_to_full_name?
  end

  def expired?
    expiry_date ? expiry_date < Time.zone.today : false
  end

  def assign_kyc_data(kyc_data)
    unless self.PAN.casecmp?(kyc_data.pan&.to_s&.strip)
      e = StandardError.new("PAN number does not match the KYC data")
      errors.add(:PAN, "does not match the KYC data")
    end
    self.full_name = kyc_data.full_name
    self.address = kyc_data.perm_address
    self.corr_address = kyc_data.corr_address
    # add below images as attached documents
    kyc_data.get_image_data.each do |image_data|
      imgtype = image_data['image_type']
      file_name = "#{kyc_data.source.upcase}Data-#{id}-#{full_name.delete('/')}-#{imgtype}.png"
      file_path = "tmp/#{file_name}"
      if imgtype.casecmp?("signature")
        Rails.logger.debug { "Uploading new image - #{file_name}" }
        Rails.root.join(file_path).binwrite(Base64.decode64(image_data['data']))
        self.signature = File.open(file_path, "rb")
      elsif imgtype.casecmp?("pan")
        Rails.logger.debug { "Uploading new image - #{file_name}" }
        Rails.root.join(file_path).binwrite(Base64.decode64(image_data['data']))
        self.pan_card = File.open(file_path, "rb")
      end

      FileUtils.rm_f(file_path)
    rescue StandardError => e # caught as kyc can have improper base64 data
      Rails.logger.error { "Error while uploading file #{file_name} #{e.message}" }
    end
  end

  def remove_images
    # remove attached image documents from kyc data
  end

  # Ovveride the include with_folder method
  # rubocop:disable Rails/SkipsModelValidations
  def document_changed(document)
    grant_access_rights_to_investor(document)
    # Check if all the required docs have been uploaded
    local_docs_completed = docs_completed?
    update_column(:docs_completed, local_docs_completed) if local_docs_completed != docs_completed
  end
  # rubocop:enable Rails/SkipsModelValidations

  def commitment_pending
    committed_amount - collected_amount
  end

  # Check if all the required docs have been uploaded
  def docs_completed?
    # The required_docs depend on the kyc_type
    required_docs = individual? ? entity.entity_setting.individual_kyc_doc_list : entity.entity_setting.non_individual_kyc_doc_list
    if required_docs.present?
      required_docs = Set.new(required_docs.split(",").map(&:strip))
      uploaded_docs = Set.new(documents.pluck(:name))
      # Sometimes other docs are also uploaded - so we check for subset
      required_docs.present? && required_docs.subset?(uploaded_docs)
    else
      false
    end
  end

  def total_fund_units
    # Find all the committments this kyc is tied to
    entity.fund_units.joins(capital_commitment: :investor_kyc).where("investor_kycs.id=?", id).sum(:quantity)
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[PAN full_name kyc_type address bank_name bank_branch bank_account_type bank_account_number ifsc_code birth_date verified expiry_date collected_amount committed_amount call_amount distribution_amount docs_completed].sort
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
end
