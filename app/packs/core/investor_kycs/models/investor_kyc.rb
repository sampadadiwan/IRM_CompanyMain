class InvestorKyc < ApplicationRecord
  # Make all models searchable
  update_index('investor_kyc') { self }
  include WithCustomField
  include Trackable
  include WithFolder

  belongs_to :investor
  belongs_to :entity
  has_many :capital_commitments

  has_many :aml_reports, dependent: :destroy
  has_many :kyc_datas, dependent: :destroy
  scope :verified, -> { where(verified: true) }
  enum :kyc_type, { individual: "Individual", non_individual: "Non Individual" }
  enum :residency, { domestic: "Domestic", foreign: "Foreign" }

  include FileUploader::Attachment(:signature)
  include FileUploader::Attachment(:pan_card)
  include FileUploader::Attachment(:video)

  belongs_to :verified_by, class_name: "User", optional: true
  validates :PAN, presence: true

  validate :birth_date_cannot_be_in_the_future
  def birth_date_cannot_be_in_the_future
    errors.add(:birth_date, "can't be in the future") if birth_date.present? && birth_date > Date.current
  end
  # Customize form
  serialize :pan_verification_response, Hash
  serialize :bank_verification_response, Hash

  attr_accessor :user_id

  before_save :set_investor_name
  def set_investor_name
    self.investor_name = investor.investor_name
  end

  def folder_path
    "#{investor.folder_path}/KYC-#{id}/#{full_name.delete('/')}"
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

  after_commit :validate_pan_card
  def validate_pan_card
    VerifyKycPanJob.perform_later(id) if saved_change_to_PAN? || saved_change_to_full_name? || saved_change_to_pan_card_data?
  end

  after_commit :validate_bank
  def validate_bank
    VerifyKycBankJob.perform_later(id) if saved_change_to_bank_account_number? || saved_change_to_ifsc_code? || saved_change_to_full_name?
  end

  after_save :notify_kyc_updated
  def notify_kyc_updated
    # InvestorKycMailer.with(id:).notify_kyc_updated.deliver_later
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
    self.full_name = kyc_data.full_name
    self.address = kyc_data.perm_address
    self.corr_address = kyc_data.corr_address

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
end
