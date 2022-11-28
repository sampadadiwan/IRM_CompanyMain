class Offer < ApplicationRecord
  include WithFolder
  include SaleChildrenScopes

  # Make all models searchable
  update_index('offer') { self }

  belongs_to :user
  belongs_to :final_agreement_user, class_name: "User", optional: true
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
  has_many :adhaar_esigns, as: :owner, dependent: :destroy

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

  scope :cmv, ->(val) { where(custom_matching_vals: val) }
  scope :approved, -> { where(approved: true) }
  scope :pending_approval, -> { where(approved: false) }
  scope :verified, -> { where(verified: true) }
  scope :not_verified, -> { where(verified: false) }
  scope :not_final_agreement, -> { where(final_agreement: false) }
  scope :auto_match, -> { where(auto_match: true) }
  scope :pending_verification, -> { where(verified: false) }
  scope :matched, -> { where.not(interest_id: nil) }

  validates :full_name, :address, :PAN, :bank_account_number, :ifsc_code, presence: true, if: proc { |o| o.secondary_sale.finalized }

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

  def notify_approval
    OfferMailer.with(offer_id: id).notify_approval.deliver_later unless secondary_sale.no_offer_emails
  end

  after_save :notify_accept_spa, if: proc { |o| o.final_agreement && o.saved_change_to_final_agreement? }
  def notify_accept_spa
    OfferMailer.with(offer_id: id).notify_accept_spa.deliver_later unless secondary_sale.no_offer_emails
  end

  def folder_path
    "#{secondary_sale.folder_path}/Offers/#{user.full_name}-#{id}"
  end

  def document_list
    secondary_sale.seller_doc_list&.split(",")
  end

  after_save :validate_pan_card, if: proc { |o| !o.secondary_sale.disable_pan_kyc }
  def validate_pan_card
    VerifyOfferPanJob.perform_later(id) if saved_change_to_PAN? || saved_change_to_full_name? || saved_change_to_pan_card_data?
  end

  after_save :validate_bank, if: proc { |o| !o.secondary_sale.disable_bank_kyc }
  def validate_bank
    VerifyOfferBankJob.perform_later(id) if saved_change_to_bank_account_number? || saved_change_to_ifsc_code? || saved_change_to_full_name?
  end

  after_save :generate_spa
  def generate_spa
    OfferSpaJob.perform_later(id) if secondary_sale.spa && saved_change_to_verified? && verified
  end

  def compute_fees(fees)
    total_fees = []
    fees.each do |fee|
      total_fees << case fee.amount_label
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
    total_fees
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

  def self.offer_report(sale_id)
    csv = []

    s = SecondarySale.find(sale_id)
    s.offers.joins(:user).distinct.each do |o|
      sig = o.signature.present? ? 'Yes' : 'No'
      pan = o.pan_card.present? ? 'Yes' : 'No'
      docs = o.documents.collect(&:name).join(", ")
      csv << [o.id, o.user.full_name, o.user.email, o.user.sign_in_count, sig, pan, docs].join(",")
    end

    File.write("OfferCompletion.csv", csv.join("\n"))

    csv
  end

  def seller_signature_types
    self[:seller_signature_types].presence || secondary_sale&.seller_signature_types
  end

  def sign_link(phone)
    # Substitute the phone number required in the link
    esign_link["phone_number"] = phone
    esign_link
  end

  def signature_completed(signature_type, file)
    OfferEsignProvider.new(self).signature_completed(signature_type, file)
  end
end
