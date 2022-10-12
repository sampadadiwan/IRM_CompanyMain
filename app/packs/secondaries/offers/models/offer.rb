class Offer < ApplicationRecord
  include WithFolder

  belongs_to :user
  belongs_to :investor
  belongs_to :entity, touch: true
  belongs_to :secondary_sale, touch: true

  counter_culture :interest,
                  column_name: proc { |o| o.approved ? 'offer_quantity' : nil },
                  delta_column: 'quantity'

  counter_culture :secondary_sale,
                  column_name: proc { |o| o.approved ? 'total_offered_quantity' : nil },
                  delta_column: 'quantity'

  counter_culture :secondary_sale,
                  column_name: proc { |o| o.approved ? 'total_offered_amount_cents' : nil },
                  delta_column: 'amount_cents'

  # This is the holding owned by the user which is offered out
  belongs_to :holding
  # This is the buyer against which this sellers quantity is matched
  belongs_to :interest, optional: true

  belongs_to :granter, class_name: "User", foreign_key: :granted_by_user_id, optional: true
  belongs_to :buyer, class_name: "Entity", optional: true

  has_many :messages, as: :owner, dependent: :destroy

  has_many :documents, as: :owner, dependent: :destroy
  accepts_nested_attributes_for :documents, allow_destroy: true
  include FileUploader::Attachment(:signature)
  include FileUploader::Attachment(:spa)
  include FileUploader::Attachment(:pan_card)

  # Customize form
  belongs_to :form_type, optional: true
  serialize :properties, Hash
  serialize :pan_verification_response, Hash
  serialize :bank_verification_response, Hash
  serialize :docs_uploaded_check, Hash

  delegate :quantity, to: :holding, prefix: :holding
  delegate :funding_round, to: :holding

  scope :approved, -> { where(approved: true) }
  scope :pending_approval, -> { where(approved: false) }
  scope :verified, -> { where(verified: true) }
  scope :auto_match, -> { where(auto_match: true) }
  scope :pending_verification, -> { where(verified: false) }

  validates :first_name, :last_name, :address, :PAN, :bank_account_number, :ifsc_code, presence: true, if: proc { |o| o.secondary_sale.finalized }

  validates :address_proof, :id_proof, :signature, presence: true if Rails.env.production?

  validate :check_quantity
  validate :sale_active, on: :create

  monetize :amount_cents, :allocation_amount_cents, with_currency: ->(o) { o.entity.currency }

  BUYER_STATUS = %w[Confirmed Rejected].freeze

  # def already_offered
  #   errors.add(:secondary_sale, ": An existing offer from this user already exists. Pl modify or delete that one.") if secondary_sale.offers.where(user_id:, holding_id:).first.present?
  # end

  def sale_active
    errors.add(:secondary_sale, ": Is not active.") unless secondary_sale.active?
  end

  before_save :set_defaults
  def set_defaults
    self.percentage = (100.0 * quantity) / total_holdings_quantity

    self.investor_id = holding.investor_id
    self.user_id = holding.user_id if holding.user_id
    self.entity_id = holding.entity_id

    self.approved = false if quantity_changed?

    self.amount_cents = quantity * final_price * 100 if final_price.positive?
    self.allocation_amount_cents = allocation_quantity * final_price * 100 if final_price.positive?
    self.docs_uploaded_check ||= {}
    self.bank_verification_response ||= {}
    self.pan_verification_response ||= {}
  end

  def check_quantity
    # holding users total holding amount
    total_quantity = total_holdings_quantity
    Rails.logger.debug { "total_holdings_quantity: #{total_quantity}" }

    # already offered amount
    already_offered = secondary_sale.offers.where(user_id: holding.user_id).sum(:quantity)
    Rails.logger.debug { "already_offered: #{already_offered}" }

    total_offered_quantity = already_offered + quantity
    total_offered_quantity -= quantity_was unless new_record?
    Rails.logger.debug { "total_offered_quantity: #{total_offered_quantity}" }

    # errors.add(:quantity, "Total offered quantity #{total_offered_quantity} is > allowed_quantity #{allowed_quantity}") if total_offered_quantity > allowed_quantity
    errors.add(:quantity, "Total offered quantity #{total_offered_quantity} is > total holdings #{total_quantity}") if total_offered_quantity > total_quantity
  end

  def total_holdings_quantity
    holding.user ? holding.user.holdings.eq_and_pref.sum(:quantity) : holding.investor.holdings.eq_and_pref.sum(:quantity)
  end

  def allowed_quantity
    # holding users total holding amount
    (total_holdings_quantity * secondary_sale.percent_allowed / 100).round
  end

  def break_offer(allocation_qtys)
    Rails.logger.debug { "breaking offer #{id} into #{allocation_qtys} pieces" }

    # Duplicate the offer
    dup_offers = [self]
    (1..allocation_qtys.length - 1).each do |_i|
      dup_offers << dup
    end

    Offer.transaction do
      # Update the peices with the quantites
      dup_offers.each_with_index do |dup_offer, i|
        diff = dup_offer.allocation_quantity - allocation_qtys[i]
        dup_offer.allocation_quantity = allocation_qtys[i]
        dup_offer.quantity -= diff
        dup_offer.save!
      end
    end
  end

  def notify_approval
    OfferMailer.with(offer_id: id).notify_approval.deliver_later unless secondary_sale.no_offer_emails
  end

  def setup_folder_details
    parent_folder = secondary_sale.document_folder.folders.where(name: "Offers").first
    setup_folder(parent_folder, user.full_name, [])
  end

  def document_list
    secondary_sale.seller_doc_list&.split(",")
  end

  after_save :validate_pan_card
  def validate_pan_card
    VerifyOfferPanJob.perform_later(id) if saved_change_to_PAN? || saved_change_to_first_name? || saved_change_to_last_name? || saved_change_to_middle_name? || saved_change_to_pan_card_data?
  end

  after_save :validate_bank
  def validate_bank
    VerifyOfferBankJob.perform_later(id) if saved_change_to_bank_account_number? || saved_change_to_ifsc_code? || saved_change_to_first_name? || saved_change_to_last_name? || saved_change_to_middle_name?
  end

  after_save :generate_spa
  def generate_spa
    OfferSpaJob.perform_later(id) if secondary_sale.spa && saved_change_to_verified? && verified
  end
end
