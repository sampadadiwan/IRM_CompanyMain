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
  include FileUploader::Attachment(:video)

  # Customize form
  belongs_to :form_type, optional: true
  serialize :properties, Hash
  serialize :pan_verification_response, Hash
  serialize :bank_verification_response, Hash

  def folder_path
    "#{investor.folder_path}/KYC-#{id}/#{user.full_name}"
  end

  before_validation :update_user
  # after_commit :send_notification_if_changed, if: :approved

  def update_user
    if user.nil?
      self.email = email.strip
      u = User.find_by(email:)
      if u.blank?
        # Setup a new user for this investor_entity_id
        u = User.new(first_name:, last_name:, email:, active: true, system_created: true,
                     entity_id: investor.investor_entity_id, phone:,
                     password: SecureRandom.hex(8))

        # Upload of IAs has a col to prevent confirmations, lets honour that
        unless send_confirmation
          Rails.logger.debug { "############# Skipping Confirmation for #{u.email}" }
          u.skip_confirmation!
        end

        # Save the user
        u.save!

        # If this user was created in the process of investor access and is the only user, make him company admin
        u.add_role :company_admin if u.entity.employees.count == 1

      end
      self.user = u
    end
  end

  after_commit :validate_pan_card
  def validate_pan_card
    VerifyKycPanJob.perform_later(id) if saved_change_to_PAN? || saved_change_to_full_name? || saved_change_to_pan_card_data?
  end

  after_commit :validate_bank
  def validate_bank
    VerifyKycBankJob.perform_later(id) if saved_change_to_bank_account_number? || saved_change_to_ifsc_code? || saved_change_to_full_name?
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

  scope :for_advisor, lambda { |user|
    # Ensure the access rghts for Document
    joins(entity: :investors)
      .where("investors.category=? and investors.investor_entity_id=?", 'Advisor', user.entity_id)
  }
end
