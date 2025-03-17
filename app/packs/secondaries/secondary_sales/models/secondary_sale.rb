class SecondarySale < ApplicationRecord
  include Trackable.new

  include WithFolder
  include WithDataRoom
  include SecondarySaleNotifiers
  include SaleAccessScopes
  include WithCustomField
  include InvestorsGrantedAccess
  include ForInvestor
  include WithCustomNotifications
  include WithIncomingEmail

  # Make all models searchable
  update_index('secondary_sale') { self if index_record? }

  SALE_TYPES = %w[Regular Tranche].freeze

  belongs_to :entity

  include FileUploader::Attachment(:spa)

  has_many :offers, dependent: :destroy
  has_many :interests, dependent: :destroy
  has_many :allocations, dependent: :destroy
  has_many :access_rights, as: :owner, dependent: :destroy
  has_many :fees, as: :owner, dependent: :destroy

  belongs_to :secondary_sale_form_type, class_name: "FormType", optional: true
  belongs_to :offer_form_type, class_name: "FormType", optional: true
  belongs_to :interest_form_type, class_name: "FormType", optional: true

  # List of employee ids to notify
  serialize :notification_employee_ids, type: Array

  monetize :total_offered_amount_cents, :total_interest_amount_cents, :allocation_amount_cents,
           with_currency: ->(s) { s.entity.currency }

  validates_uniqueness_of :name, scope: :entity_id

  validates :name, :start_date, :end_date, :percent_allowed, presence: true
  validates :final_price, numericality: { greater_than: 0 },
                          if: -> { price_type == 'Fixed Price' || finalized }
  validates :final_price, presence: true, if: -> { price_type == 'Fixed Price' }
  validates :min_price, :max_price, presence: true, if: -> { price_type == 'Price Range' }
  validates :max_price, numericality: { greater_than: :min_price }, if: -> { price_type == 'Price Range' }

  validates :name, :support_email, length: { maximum: 255 }
  validates :allocation_status, :sale_type, :show_quantity, length: { maximum: 10 }
  validates :price_type, length: { maximum: 15 }
  validates :name, length: { maximum: 255 }

  scope :active, -> { where(end_date: Time.zone.today..) }

  before_save :set_defaults
  def set_defaults
    self.price_type ||= "Price Range"
    if price_type == "Fixed Price"
      self.min_price = final_price
      self.max_price = final_price
    end
    self.show_quantity ||= "Actual"
    self.manage_offers = true if id.nil?
    self.manage_interests = true if id.nil?
  end

  def active?
    Time.zone.today.between?(start_date, end_date)
  end

  def clearing_price
    interests = self.interests.short_listed
    interest_quantity = interests.sum(:quantity)
    offer_quantity = offers.approved.sum(:quantity)

    if interest_quantity.zero?
      logger.debug "No interests for #{name}, clearing price is 0"
      0
    elsif interest_quantity <= offer_quantity
      cp = interests.minimum(:price)
      logger.debug "Interests for #{name} are less than or equal to offers, clearing price is #{cp}"
      cp
    else
      qty = 0
      interests.order(price: :desc).each do |interest|
        logger.debug "Interest #{interest.id} has quantity #{interest.quantity} & price #{interest.price}"
        qty += interest.quantity
        return interest.price if qty >= offer_quantity
      end
    end
  end

  def to_s
    name
  end

  def folder_path
    "/Secondary Sales/#{name.delete('/')}"
  end

  def document_tags
    ["Buyer", "Buyer Template", "Offer Template", "Seller", "Allocation Template"]
  end

  def signature_labels
    ["Buyer Signatories", "Seller Signatories", "Other"]
  end

  def buyer_investors
    investors_granted_access("Buyer")
  end

  def seller_investors
    investors_granted_access("Seller")
  end

  def display_quantity
    self.show_quantity == "Indicative" ? indicative_quantity : total_offered_quantity
  end

  def display_price
    self.price_type == "Fixed Price" ? final_price.to_s : "#{min_price} - #{max_price}"
  end

  def display_amounts
    self.price_type == "Fixed Price" ? [Money.new(display_quantity * final_price * 100, entity.currency)] : [Money.new(display_quantity * min_price * 100, entity.currency), Money.new(display_quantity * max_price * 100, entity.currency)]
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[active start_date]
  end

  def adhoc_notifications_to
    ["All Sellers", "All Buyers", "Approved Sellers", "Verified Sellers", "Shortlisted Buyers"].sort
  end

  def notification_users
    if notification_employee_ids.present?
      entity.employees.where(id: notification_employee_ids)
    else
      []
    end
  end
end
