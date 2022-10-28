class InvestorKyc < ApplicationRecord
  # Make all models searchable
  update_index('investor_kyc') { self }

  include WithFolder

  belongs_to :investor
  belongs_to :entity
  belongs_to :user

  scope :verified, -> { where(verified: true) }

  has_many :documents, as: :owner, dependent: :destroy
  accepts_nested_attributes_for :documents, allow_destroy: true

  include FileUploader::Attachment(:signature)
  include FileUploader::Attachment(:pan_card)

  # Customize form
  belongs_to :form_type, optional: true
  serialize :properties, Hash
  serialize :pan_verification_response, Hash
  serialize :bank_verification_response, Hash

  def setup_folder_details
    parent_folder = investor.document_folder.folders.where(name: "KYC").first
    setup_folder(parent_folder, user.full_name, [])
  end

  after_commit :validate_pan_card
  def validate_pan_card
    VerifyKycPanJob.perform_later(id) if saved_change_to_PAN? || saved_change_to_first_name? || saved_change_to_last_name? || saved_change_to_middle_name? || saved_change_to_pan_card_data?
  end

  after_commit :validate_bank
  def validate_bank
    VerifyKycBankJob.perform_later(id) if saved_change_to_bank_account_number? || saved_change_to_ifsc_code? || saved_change_to_first_name? || saved_change_to_last_name? || saved_change_to_middle_name?
  end

  after_commit :update_user_signature
  def update_user_signature
    if signature.present? && user.signature.blank?
      user.signature = signature
      user.save
    end
  end

  after_save :notify_kyc_updated
  def notify_kyc_updated
    InvestorKycMailer.with(id:).notify_kyc_updated.deliver_later
  end

  scope :for_accountant, lambda { |user|
    # Ensure the access rghts for Document
    joins(entity: :investors)
      .where("investors.category=? and investors.investor_entity_id=?", 'Accountant', user.entity_id)
  }
end
