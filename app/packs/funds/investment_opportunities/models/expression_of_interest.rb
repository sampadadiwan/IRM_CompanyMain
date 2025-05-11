# EOIs are used to express interest in an investment opportunity. They can be created by investors and are associated with a specific investment opportunity. The EOI includes details such as the amount, allocation percentage, and whether it has been approved.

# The EOI can be created by RMs for their clients. The difference is when the EOI is approved the RMs client will be converted to the Funds investor, and the KYC associated with the EOI will be repointed to the new Investor. See EoiApprove

class ExpressionOfInterest < ApplicationRecord
  include WithFolder
  include ForInvestor

  # === Associations ===
  belongs_to :entity
  belongs_to :user
  belongs_to :investor # Can be an end investor or RM
  belongs_to :eoi_entity, class_name: "Entity"
  belongs_to :investment_opportunity
  belongs_to :investor_kyc, optional: true
  belongs_to :investor_signatory, class_name: "User", optional: true

  has_many :noticed_events, as: :record, dependent: :destroy, class_name: "Noticed::Event"

  # === Rich Text ===
  has_rich_text :details

  # === Serialized Fields ===
  serialize :properties, type: Hash

  # === Validations ===
  validates :investor_name, length: { maximum: 100 }
  validates :investor_email, length: { maximum: 255 }
  validates_format_of :investor_email, with: URI::MailTo::EMAIL_REGEXP, multiline: true, if: -> { investor_email.present? }

  validate :check_amount

  # === Counter Cache for approved EOIs only ===
  counter_culture :investment_opportunity,
                  column_name: ->(eoi) { eoi.approved ? 'eoi_amount_cents' : nil },
                  delta_column: 'amount_cents',
                  column_names: {
                    ["expression_of_interests.approved = ?", true] => 'eoi_amount_cents'
                  }

  # === Monetize ===
  monetize :amount_cents, :allocation_amount_cents,
           with_currency: ->(eoi) { eoi.investment_opportunity.currency }

  # === Scopes ===
  scope :approved, -> { where(approved: true) }

  # === Callbacks ===
  before_save :update_approval
  before_save :update_percentage
  before_save :notify_approved
  after_create_commit :give_access_rights

  # === Validation Methods ===

  # Ensure amount is within the allowed range for the opportunity
  def check_amount
    errors.add(:amount, "Should be greater than #{investment_opportunity.min_ticket_size}") if amount < investment_opportunity.min_ticket_size

    errors.add(:amount, "Should be less than #{investment_opportunity.fund_raise_amount}") if amount > investment_opportunity.fund_raise_amount
  end

  # === Callback Methods ===

  # Reset approval if the amount changes
  def update_approval
    self.approved = false if amount_cents_changed?
  end

  # Calculate percentage allocated based on approved amount
  def update_percentage
    self.allocation_percentage = (100.0 * allocation_amount_cents / amount_cents)
  end

  # Notify users if EOI has just been approved
  def notify_approved
    return unless approved && approved_changed?

    investor.notification_users.each do |user|
      ExpressionOfInterestNotifier.with(record: self, entity_id:).deliver_later(user)
    end
  end

  # Grant investor access rights to the investment opportunity after EOI creation
  def give_access_rights
    AccessRight.create(
      entity_id:,
      owner: investment_opportunity,
      investor:,
      access_type: "InvestmentOpportunity",
      metadata: "Investor"
    )
  end

  # === Helper Methods ===

  # Path for storing EOI-related documents
  def folder_path
    "#{investment_opportunity.folder_path}/EOI/#{eoi_entity.name.delete('/')}"
  end

  # List of documents investor needs to submit
  def document_list
    investment_opportunity.buyer_docs_list&.split(",")
  end

  ################# eSign stuff follows ###################
end
