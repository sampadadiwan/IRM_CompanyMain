class Interest < ApplicationRecord
  include Trackable.new
  include WithFolder
  include SaleChildrenScopes
  include WithCustomField
  include ForInvestor
  include WithIncomingEmail

  belongs_to :user
  belongs_to :investor
  belongs_to :final_agreement_user, class_name: "User", optional: true
  belongs_to :secondary_sale, touch: true
  belongs_to :interest_entity, class_name: "Entity"
  belongs_to :entity, touch: true

  has_many :offers, dependent: :destroy
  has_many :tasks, as: :owner, dependent: :destroy
  has_many :messages, as: :owner, dependent: :destroy
  has_many :noticed_events, as: :record, dependent: :destroy, class_name: "Noticed::Event"
  has_many :access_rights, through: :secondary_sale

  include FileUploader::Attachment(:spa)

  has_rich_text :details

  validates :quantity, comparison: { less_than_or_equal_to: :display_quantity }
  validates :price, comparison: { less_than_or_equal_to: :max_price }, if: -> { secondary_sale.price_type == 'Price Range' }
  validates :price, comparison: { greater_than_or_equal_to: :min_price }, if: -> { secondary_sale.price_type == 'Price Range' }

  validates :price, comparison: { equal_to: :final_price }, if: -> { secondary_sale.price_type == 'Fixed Price' }

  validates :buyer_entity_name, length: { maximum: 100 }
  validates :contact_name, length: { maximum: 50 }
  validates :email, length: { maximum: 100 }
  validates :buyer_signatory_emails, length: { maximum: 255 }
  validates :PAN, length: { maximum: 15 }
  validates :demat, :city, :ifsc_code, length: { maximum: 20 }
  validates :bank_account_number, length: { maximum: 15 }

  delegate :display_quantity, to: :secondary_sale
  delegate :min_price, to: :secondary_sale
  delegate :max_price, to: :secondary_sale
  delegate :final_price, to: :secondary_sale
  delegate :email, to: :user, prefix: true

  scope :cmv, ->(val) { where(custom_matching_vals: val) }
  scope :short_listed, -> { where(short_listed: true) }
  scope :not_short_listed, -> { where(short_listed: false) }
  scope :not_final_agreement, -> { where(final_agreement: false) }
  scope :escrow_deposited, -> { where(escrow_deposited: true) }
  scope :priced_above, ->(price) { where(price: price..) }
  scope :priced_below, ->(price) { where(price: ...price) }
  scope :eligible, ->(secondary_sale) { short_listed.priced_above(secondary_sale.final_price) }
  scope :not_eligible, ->(secondary_sale) { short_listed.priced_below(secondary_sale.final_price) }

  before_validation :set_defaults

  validates :quantity, :price, presence: true
  validates :buyer_entity_name, :address, :city, :PAN, :contact_name, presence: true, if: proc { |i| i.verified }

  serialize :pan_verification_response, type: Hash
  serialize :bank_verification_response, type: Hash

  monetize :amount_cents, :allocation_amount_cents, with_currency: ->(i) { i.entity.currency }

  counter_culture :secondary_sale,
                  column_name: proc { |o| o.short_listed ? 'total_interest_quantity' : nil },
                  delta_column: 'quantity'

  counter_culture :secondary_sale,
                  column_name: proc { |o| o.short_listed ? 'total_interest_amount_cents' : nil },
                  delta_column: 'amount_cents'

  def notify_interest
    unless secondary_sale.no_interest_emails
      investor.notification_users.each do |user|
        InterestNotifier.with(record: self, entity_id:, email_method: :notify_interest, msg: "Interest received for #{secondary_sale.name}").deliver_later(user)
      end
    end
  end

  def notify_shortlist
    if short_listed && saved_change_to_short_listed? && !secondary_sale.no_interest_emails
      investor.notification_users.each do |user|
        InterestNotifier.with(record: self, entity_id:, email_method: :notify_shortlist, msg: "Interest shortlisted for #{secondary_sale.name}").deliver_later(user)
      end
    end
  end

  def notify_accept_spa
    unless secondary_sale.no_interest_emails
      investor.notification_users.each do |user|
        InterestNotifier.with(record: self, entity_id:, email_method: :notify_accept_spa, msg: "SPA confirmation received for #{secondary_sale.name}").deliver_later(user)
      end
    end
  end

  def to_s
    "#{investor&.investor_name} - #{quantity} shares @ #{price}"
  end

  def applied_price
    final_price.positive? ? final_price : price
  end

  def set_defaults
    self.entity_id ||= secondary_sale.entity_id
    self.investor ||= entity.investors.where(investor_entity_id: user.entity_id).first
    self.interest_entity_id ||= investor.investor_entity_id

    self.amount_cents = quantity * applied_price * 100
    self.allocation_amount_cents = allocation_quantity * applied_price * 100

    self.custom_matching_vals = ""
    if secondary_sale.custom_matching_fields.present?
      secondary_sale.custom_matching_fields.split(",").each do |cmf|
        # For each custom matching field, we extract the value from the offers
        val = eval <<-RUBY, binding, __FILE__, __LINE__ + 1
              self.#{cmf} # Evaluate the custom_matching_fields
        RUBY
        self.custom_matching_vals += "#{val}_"
      end
    else
      self.custom_matching_vals = ""
    end
  end

  def allocation_delta
    allocation_quantity - offer_quantity
  end

  def folder_path
    "#{secondary_sale.folder_path}/Interests/#{interest_entity.name.delete('/')}-#{id}"
  end

  def offer_amount
    Money.new(offer_quantity * final_price * 100, entity.currency)
  end

  def signature
    documents.where("name like ?", "%Signature%").last&.file
  end

  def document_list
    secondary_sale.buyer_doc_list&.split(",")
  end

  def aquirer_name
    buyer_entity_name.presence || interest_entity.name
  end

  def notification_emails
    # Check if this is by an investor - if so send to all in investor access
    @investor ||= Investor.where(entity_id:, investor_entity_id: interest_entity_id).first
    if @investor
      @investor.emails
    else
      # Else send it to the interest user only
      [user.email]
    end
  end

  def validate_pan_card
    should_validate_pan = (saved_change_to_PAN? && self.PAN.present?) ||
                          (saved_change_to_buyer_entity_name? && buyer_entity_name.present?) ||
                          (self.PAN.present? && buyer_entity_name.present? && pan_verification_response.blank?)

    return unless should_validate_pan

    if Rails.env.test?
      VerifyPanJob.perform_now(obj_class: self.class.to_s, obj_id: id)
    else
      VerifyPanJob.set(wait: rand(300).seconds).perform_later(obj_class: self.class.to_s, obj_id: id)
    end
  end

  def pan_card
    documents.where("name like ?", "%PAN%").last&.file
  end

  def validate_bank
    should_validate_bank = (saved_change_to_bank_account_number? && bank_account_number.present?) ||
                           (saved_change_to_buyer_entity_name? && buyer_entity_name.present?) ||
                           (saved_change_to_ifsc_code? && ifsc_code.present?) ||
                           (bank_account_number.present? && ifsc_code.present? && buyer_entity_name.present? && bank_verification_response.blank?)

    return unless should_validate_bank

    if Rails.env.test?
      VerifyBankJob.perform_now(obj_class: self.class.to_s, obj_id: id)
    else
      VerifyBankJob.set(wait: rand(300).seconds).perform_later(obj_class: self.class.to_s, obj_id: id)
    end
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[PAN address allocation_amount allocation_percentage allocation_quantity amount bank_account_number buyer_entity_name city contact_name demat email entity_id ifsc_code quantity short_listed verified]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[secondary_sale investor]
  end
end
