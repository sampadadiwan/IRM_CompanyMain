class Interest < ApplicationRecord
  include Trackable.new
  include WithFolder
  include SaleChildrenScopes
  include WithCustomField
  include ForInvestor
  include WithIncomingEmail
  include WithAllocations

  STANDARD_COLUMNS = {
    "Buyer Entity" => "buyer_entity_name",
    "Investor" => "investor_name",
    "User" => "user",
    "Quantity" => "quantity",
    "Price" => "price",
    "Allocation Quantity" => "allocation_quantity",
    "Allocation Amount" => "allocation_amount",
    "Status" => "short_listed_status",
    "Verified" => "verified",
    "Created At" => "created_at"
  }.freeze

  belongs_to :user, optional: true
  belongs_to :investor
  belongs_to :final_agreement_user, class_name: "User", optional: true
  belongs_to :secondary_sale, touch: true
  belongs_to :interest_entity, class_name: "Entity"
  belongs_to :entity, touch: true

  has_many :tasks, as: :owner, dependent: :destroy
  has_many :messages, as: :owner, dependent: :destroy
  has_many :noticed_events, as: :record, dependent: :destroy, class_name: "Noticed::Event"
  has_many :offers, through: :allocations

  include FileUploader::Attachment(:spa)

  has_rich_text :details

  # validates :quantity, comparison: { less_than_or_equal_to: :display_quantity }
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

  # 1. Define possible statuses as constants
  STATUS_PENDING = 'pending'.freeze
  STATUS_SHORT_LISTED = 'short_listed'.freeze
  STATUS_REJECTED = 'rejected'.freeze
  STATUS_WITHDRAWN = 'withdrawn'.freeze

  STATUSES = [STATUS_PENDING, STATUS_SHORT_LISTED, STATUS_REJECTED, STATUS_WITHDRAWN].freeze
  belongs_to :status_updated_by, class_name: "User", optional: true

  # 2. Validations
  validates :short_listed_status, presence: true, inclusion: { in: STATUSES }

  # 3. Scopes for easy querying
  scope :pending, -> { where(short_listed_status: STATUS_PENDING) }
  scope :short_listed, -> { where(short_listed_status: STATUS_SHORT_LISTED) }
  scope :not_short_listed, -> { where.not(short_listed_status: STATUS_SHORT_LISTED) }
  scope :rejected, -> { where(short_listed_status: STATUS_REJECTED) }
  scope :withdrawn, -> { where(short_listed_status: STATUS_WITHDRAWN) }

  scope :cmv, ->(val) { where(custom_matching_vals: val) }
  scope :verified, -> { where(verified: true) }
  scope :unverified, -> { where(verified: false) }
  scope :completed, -> { where(completed: true) }
  scope :incomplete, -> { where(completed: false) }

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
      msg = "Interest received for #{investor.investor_name}:#{buyer_entity_name} in #{secondary_sale.name}"
      send_notification(:notify_interest, msg)
    end
  end

  def notify_shortlist
    if saved_change_to_short_listed_status? && !secondary_sale.no_interest_emails
      msg = "Interest #{short_listed_status.humanize} for #{investor.investor_name}:#{buyer_entity_name} in #{secondary_sale.name}"
      send_notification(:notify_shortlist, msg)
    end
  end

  def notify_accept_spa
    unless secondary_sale.no_interest_emails
      msg = "SPA confirmation received for #{investor.investor_name}:#{buyer_entity_name} in #{secondary_sale.name}"
      send_notification(:notify_accept_spa, msg)
    end
  end

  def send_notification(email_method, msg)
    # Notifiy the investor
    investor.notification_users.each do |user|
      InterestNotifier.with(record: self, entity_id:, email_method:, msg:).deliver_later(user)
    end
    # Notify the RM
    investor.rm_mappings.each do |rm_mapping|
      rm_mapping.rm.notification_users.each do |user|
        InterestNotifier.with(record: self, entity_id:, email_method:, msg:).deliver_later(user)
      end
    end
    # Notify the entity
    secondary_sale.notification_users.each do |user|
      InterestNotifier.with(record: self, entity_id:, email_method:, msg:).deliver_later(user)
    end
  end

  def short_listed
    short_listed_status == STATUS_SHORT_LISTED
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
    self.price = secondary_sale.final_price if secondary_sale.price_type == 'Fixed Price'

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
    "#{secondary_sale.folder_path}/Interests/#{interest_entity.name.delete('/')}-#{id_or_random_int}"
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
      VerifyPanJob.set(wait: rand(VerifyBankJob::DELAY_SECONDS).seconds).perform_later(obj_class: self.class.to_s, obj_id: id)
    end
  end

  def pan_card
    documents.where(owner_tag: "PAN").last&.file
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
      VerifyBankJob.set(wait: rand(VerifyBankJob::DELAY_SECONDS).seconds).perform_later(obj_class: self.class.to_s, obj_id: id)
    end
  end

  include RansackerAmounts.new(fields: %w[allocation_amount])

  def self.ransackable_attributes(_auth_object = nil)
    %w[PAN address allocation_amount allocation_quantity amount bank_account_number buyer_entity_name city contact_name demat email entity_id ifsc_code quantity short_listed_status quantity price verified escrow_deposited created_at]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[secondary_sale investor user]
  end

  def unverified_allocation_quantity
    allocations.unverified.sum(:quantity)
  end

  def total_available_quantity
    quantity - total_allocation_quantity
  end

  def total_allocation_quantity
    allocations.sum(:quantity)
  end
end
