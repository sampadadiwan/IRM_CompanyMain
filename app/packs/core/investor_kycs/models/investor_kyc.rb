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
end
