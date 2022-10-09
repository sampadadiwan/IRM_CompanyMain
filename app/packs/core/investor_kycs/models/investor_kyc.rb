class InvestorKyc < ApplicationRecord
  include WithFolder

  belongs_to :investor
  belongs_to :entity
  belongs_to :user

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

  after_save :validate_pan_card
  def validate_pan_card
    VerifyKycPanJob.perform_later(id) if saved_change_to_PAN? || saved_change_to_first_name? || saved_change_to_last_name? || saved_change_to_middle_name? || saved_change_to_pan_card_data?
  end

  after_save :validate_bank
  def validate_bank
    VerifyKycBankJob.perform_later(id) if saved_change_to_bank_account_number? || saved_change_to_ifsc_code? || saved_change_to_first_name? || saved_change_to_last_name? || saved_change_to_middle_name?
  end
end
