class InvestorKyc < ApplicationRecord
  # Make all models searchable
  update_index('investor_kyc') { self }
  include Trackable
  include WithFolder

  belongs_to :investor
  belongs_to :entity

  scope :verified, -> { where(verified: true) }

  has_many :documents, as: :owner, dependent: :destroy
  accepts_nested_attributes_for :documents, allow_destroy: true

  include FileUploader::Attachment(:signature)
  include FileUploader::Attachment(:pan_card)
  include FileUploader::Attachment(:video)

  belongs_to :verified_by, class_name: "User", optional: true

  # Customize form
  belongs_to :form_type, optional: true
  serialize :properties, Hash
  serialize :pan_verification_response, Hash
  serialize :bank_verification_response, Hash

  before_save :set_investor_name
  def set_investor_name
    self.investor_name = investor.investor_name
  end

  def folder_path
    "#{investor.folder_path}/KYC-#{id}/#{full_name}"
  end

  def document_list
    # fund.commitment_doc_list&.split(",")
    docs = entity.kyc_doc_list.split(",").map(&:strip) if entity.kyc_doc_list.present?
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
    InvestorKycMailer.with(id:).notify_kyc_updated.deliver_later
  end

  scope :for_advisor, lambda { |user|
    # Ensure the access rghts for Document
    joins(entity: :investors)
      .where("investors.category=? and investors.investor_entity_id=?", 'Advisor', user.entity_id)
  }
end
