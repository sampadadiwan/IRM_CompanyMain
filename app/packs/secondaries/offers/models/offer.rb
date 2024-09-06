class Offer < ApplicationRecord
  include Trackable.new
  include WithFolder
  include SaleChildrenScopes
  include WithCustomField
  include ForInvestor
  include WithIncomingEmail

  STANDARD_COLUMN_NAMES = ["User", "Investor", "Quantity", "Allocation Quantity", "Allocation %", "Price", "Allocation Amount", "Approved", "Verified", "Updated At", " "].freeze
  STANDARD_COLUMN_FIELDS = %w[user investor_name quantity allocation_quantity allocation_percentage final_price allocation_amount approved verified updated_at dt_actions].freeze

  INVESTOR_COLUMN_NAMES = ["User", "Quantity", "Allocation Quantity", "Price", "Allocation Amount", " "].freeze
  INVESTOR_COLUMN_FIELDS = %w[user quantity allocation_quantity final_price allocation_amount dt_actions].freeze

  # Make all models searchable
  update_index('offer') { self if index_record? }

  # Normalize the address to remove newline chars
  normalizes :address, with: ->(address) { address.gsub(/\r?\n/, ' ') }

  belongs_to :user
  belongs_to :final_agreement_user, class_name: "User", optional: true
  belongs_to :investor
  belongs_to :entity, touch: true
  belongs_to :secondary_sale, touch: true
  has_many :noticed_events, as: :record, dependent: :destroy, class_name: "Noticed::Event"

  has_many :access_rights, through: :secondary_sale

  counter_culture :interest,
                  column_name: proc { |o| o.approved ? 'offer_quantity' : nil },
                  delta_column: 'quantity', column_names: -> { { Offer.approved => 'offer_quantity' } }

  counter_culture :secondary_sale,
                  column_name: proc { |o| o.approved ? 'total_offered_quantity' : nil },
                  delta_column: 'quantity', column_names: -> { { Offer.approved => 'total_offered_quantity' } }

  counter_culture :secondary_sale,
                  column_name: proc { |o| o.approved ? 'total_offered_amount_cents' : nil },
                  delta_column: 'amount_cents', column_names: -> { { Offer.approved => 'total_offered_amount_cents' } }

  # This is the holding owned by the user which is offered out
  belongs_to :holding, optional: true
  # This is the buyer against which this sellers quantity is matched
  belongs_to :interest, optional: true

  belongs_to :granter, class_name: "User", foreign_key: :granted_by_user_id, optional: true
  belongs_to :buyer, class_name: "Entity", optional: true

  # has_many :messages, as: :owner, dependent: :destroy
  include FileUploader::Attachment(:spa)

  serialize :pan_verification_response, type: Hash
  serialize :bank_verification_response, type: Hash
  serialize :docs_uploaded_check, type: Hash

  delegate :quantity, to: :holding, prefix: :holding
  delegate :funding_round, to: :holding

  scope :cmv, ->(val) { where(custom_matching_vals: val) }
  scope :approved, -> { where(approved: true) }
  scope :pending_approval, -> { where(approved: false) }
  scope :verified, -> { where(verified: true) }
  scope :not_verified, -> { where(verified: false) }
  scope :not_final_agreement, -> { where(final_agreement: false) }
  scope :auto_match, -> { where(auto_match: true) }
  scope :matched, -> { where.not(interest_id: nil) }

  validates :full_name, :address, :PAN, :bank_account_number, :ifsc_code, presence: true, if: proc { |o| o.verified }

  validate :check_quantity, if: proc { |o| o.holding.present? }
  validate :sale_active, on: :create
  validates :offer_type, :PAN, length: { maximum: 15 }
  validates :bank_account_number, :demat, length: { maximum: 40 }
  validates :ifsc_code, :city, length: { maximum: 20 }

  validates :bank_name, length: { maximum: 50 }
  validates :buyer_confirmation, length: { maximum: 10 }
  validates :acquirer_name, :seller_signatory_emails, length: { maximum: 255 }
  validates :full_name, length: { maximum: 100 }

  monetize :amount_cents, :allocation_amount_cents, with_currency: ->(o) { o.entity.currency }

  BUYER_STATUS = %w[Confirmed Rejected].freeze

  def sale_active
    errors.add(:secondary_sale, ": Is not active.") unless secondary_sale.active?
  end

  before_save :set_defaults
  def set_defaults
    if holding.present?
      self.percentage = (100.0 * quantity) / total_holdings_quantity
      self.investor_id = holding.investor_id
      self.user_id = holding.user_id if holding.user_id
      self.entity_id = holding.entity_id
      self.offer_type ||= holding.holding_type
    end

    self.approved = false if quantity_changed?

    if final_price.positive?
      self.amount_cents = quantity * final_price * 100 
      self.allocation_amount_cents = allocation_quantity * final_price * 100 
    elsif self.interest.present?
      self.amount_cents = quantity * interest.price * 100 
      self.allocation_amount_cents = allocation_quantity * interest.price * 100  
    end
    self.docs_uploaded_check ||= {}
    self.bank_verification_response ||= {}
    self.pan_verification_response ||= {}

    set_custom_matching_vals
  end

  def set_custom_matching_vals
    self.custom_matching_vals = ""
    if secondary_sale.custom_matching_fields.present?
      secondary_sale.custom_matching_fields.split(",").each do |cmf|
        # For each custom matching field, we extract the value from the offers
        val = eval <<-RUBY, binding, __FILE__, __LINE__ + 1
              self.#{cmf} # Evaluate the custom_matching_fields
        RUBY
        self.custom_matching_vals += "#{val}_"
      end
    end
  end

  # This is used to validate the quantity of the offer
  # This is applicable only for the offers tied to a holding
  def check_quantity
    # holding users total holding amount
    total_quantity = total_holdings_quantity
    Rails.logger.debug { "total_holdings_quantity: #{total_quantity}" }

    # already offered amount
    already_offered = secondary_sale.offers.where(user_id: holding.user_id).sum(:quantity)
    Rails.logger.debug { "already_offered: #{already_offered}" }

    already_offered -= quantity_was unless new_record?

    total_offered_quantity = already_offered + quantity
    total_offered_quantity -= quantity_was unless new_record?
    Rails.logger.debug { "total_offered_quantity: #{total_offered_quantity}" }

    # errors.add(:quantity, "Total offered quantity #{total_offered_quantity} is > allowed_quantity #{allowed_quantity}") if total_offered_quantity > allowed_quantity
    errors.add(:quantity, "Total offered quantity #{total_offered_quantity} is > total holdings #{total_quantity}") if total_offered_quantity > total_quantity
  end

  def total_holdings_quantity
    if holding.present?
      holding.holding_type == "Investor" ? holding.investor.holdings.approved.eq_and_pref.sum(:quantity) : holding.user.holdings.approved.eq_and_pref.sum(:quantity)
    else
      0
    end
  end

  def allowed_quantity
    if holding.present?
      # holding users total holding amount
      (total_holdings_quantity * secondary_sale.percent_allowed / 100).round
    else
      Integer::MAX
    end
  end

  def notify_approval
    OfferNotifier.with(record: self, entity_id:, email_method: :notify_approval, msg: "Offer for #{secondary_sale.name} has been approved").deliver_later(user) unless secondary_sale.no_offer_emails
  end

  def notify_accept_spa
    OfferNotifier.with(record: self, entity_id:, email_method: :notify_accept_spa, msg: "SPA confirmation received for #{secondary_sale.name}").deliver_later(user) unless secondary_sale.no_offer_emails
  end

  def folder_path
    "#{secondary_sale.folder_path}/Offers/#{user.full_name.delete('/')}-#{id}"
  end

  def document_list
    doc_list = []
    doc_list += secondary_sale.seller_doc_list&.split(",") if secondary_sale.seller_doc_list.present?

    # We also add the secondary_sale templates headers and footers
    secondary_sale.documents.where(owner_tag: "Offer Template").find_each do |doc|
      doc_list << ("#{doc.name} Header")
      doc_list << ("#{doc.name} Footer")
    end

    doc_list << "Other"
  end

  def validate_pan_card
    VerifyOfferPanJob.perform_later(id) if (saved_change_to_PAN? || saved_change_to_full_name?) && pan_card.present?
  end

  def validate_bank
    VerifyOfferBankJob.perform_later(id) if saved_change_to_bank_account_number? || saved_change_to_ifsc_code? || saved_change_to_full_name?
  end

  def generate_spa(user)
    validate_spa_generation
    return false if errors.present?

    OfferSpaJob.perform_later(secondary_sale_id, id, user.id) if saved_change_to_verified? && verified
    true
  end

  def validate_spa_generation
    errors.add(:base, "Offer #{id} is not verified!") unless verified
    errors.add(:base, "Offer #{id} is not associated with any interest!") if interest.blank?
    errors.add(:base, "No Offer Template found for Offer #{id}") if secondary_sale.documents&.where(owner_tag: "Offer Template").blank?
  end

  def compute_fees(fees)
    fees.map do |fee|
      case fee.amount_label
      when "Per Share"
        # Per Share fees
        { name: fee.advisor_name, fee: allocation_quantity * fee.amount }
      when "Percentage"
        # % of amount fees
        { name: fee.advisor_name, fee: allocation_amount * fee.amount_cents / 10_000 }
      else
        # Flat fees
        { name: fee.advisor_name, fee: fee.amount }
      end
    end
  end

  def self.compute_payments(offers, fees)
    buyer_hash = {}
    grouped_offers = offers.group_by { |o| o.interest&.buyer_entity_name }

    grouped_offers.each do |buyer_entity_name, buyer_offers|
      buyer_hash[buyer_entity_name] ||= {}
      # All the offers of this buyer
      buyer_hash[buyer_entity_name][:offers] = buyer_offers
      # Total allocation_amount for this buyer
      buyer_hash[buyer_entity_name][:total_allocation_amount] = buyer_offers.inject(Money.new(0, offers[0].entity.currency)) { |sum, o| sum + o.allocation_amount }

      # Fees for this buyer
      buyer_hash[buyer_entity_name][:fees] = buyer_fees(buyer_offers, fees, offers[0].entity.currency)
    end

    buyer_hash
  end

  def self.buyer_fees(buyer_offers, fees, currency)
    buyer_fees_hash = {}
    fees_by_advisor = buyer_offers.map { |o| o.compute_fees(fees) }.flatten.group_by { |f| f[:name] }
    fees_by_advisor.each do |advisor_name, computed_fees|
      buyer_fees_hash[advisor_name] ||= {}
      buyer_fees_hash[advisor_name][:fee_amount] = computed_fees.inject(Money.new(0, currency)) { |sum, f| sum + f[:fee] }
      buyer_fees_hash[advisor_name][:fee] = fees.find { |f| f.advisor_name == advisor_name }
    end

    buyer_fees_hash
  end

  ################# eSign stuff follows ###################

  def buyer_signatories
    self&.interest&.buyer_signatory_emails&.split(",")
  end

  def seller_signatories
    seller_signatory_emails&.split(",")
  end

  ################# ransack stuff follows ###################

  def self.ransackable_attributes(_auth_object = nil)
    %w[PAN acquirer_name address allocation_amount_cents allocation_percentage allocation_quantity amount_cents approved bank_account_number bank_name bank_routing_info bank_verification_response bank_verification_status bank_verified buyer_confirmation demat full_name ifsc_code percentage quantity verified final_agreement matched interest_id updated_at created_at].sort
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[secondary_sale investor interest user]
  end

  def self.ransackable_scopes(_auth_object = nil)
    %i[]
  end

  def pan_card
    documents.where("name like ?", "%PAN%").last&.file
  end

  def signature
    documents.where("name like ?", "%Signature%").last&.file
  end

  def to_s
    "Offer: #{user}"
  end

  ################### Adhoc fn for prod data management ##############

  def self.copy_docs(from_sale, to_sale)
    to_sale.offers.each do |to_offer|
      from_offer = from_sale.offers.where(user_id: to_offer.user_id).last
      next unless from_offer

      doc = from_offer.documents.where("name like ?", "%cheque%").last
      Document.find_or_create_by(name: doc.name, file_data: doc.file_data, owner: to_offer, entity_id: to_offer.entity_id, user_id: to_offer.user_id) if doc

      # Extract the PAN and signature
      doc = from_offer.documents.where("name like ?", "%Signature%").last
      Document.find_or_create_by(name: "Signature", file_data: doc.file_data, owner: to_offer, entity_id: to_offer.entity_id, user_id: to_offer.user_id)

      doc = from_offer.documents.where("name like ?", "%PAN%").last
      Document.find_or_create_by(name: "PAN", file_data: doc.file_data, owner: to_offer, entity_id: to_offer.entity_id, user_id: to_offer.user_id)
    end
  end
end
