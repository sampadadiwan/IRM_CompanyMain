class SecondarySale < ApplicationRecord
  include Trackable
  include ActivityTrackable
  include WithFolder
  include SecondarySaleNotifiers
  include SaleAccessScopes
  include WithCustomField
  include InvestorsGrantedAccess
  include ForInvestor

  # Make all models searchable
  update_index('secondary_sale') { self if index_record? }

  SALE_TYPES = %w[Regular Tranche].freeze

  belongs_to :entity

  include FileUploader::Attachment(:spa)

  has_many :offers, dependent: :destroy
  has_many :interests, dependent: :destroy
  has_many :access_rights, as: :owner, dependent: :destroy
  has_many :fees, as: :owner, dependent: :destroy
  has_noticed_notifications

  serialize :cmf_allocation_percentage, type: Hash

  monetize :total_offered_amount_cents, :total_interest_amount_cents,
           :allocation_offer_amount_cents, :allocation_interest_amount_cents,
           with_currency: ->(s) { s.entity.currency }

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

  before_save :set_defaults
  def set_defaults
    self.price_type ||= "Price Range"
    if price_type == "Fixed Price"
      self.min_price = final_price
      self.max_price = final_price
    end
    self.show_quantity ||= "Actual"
  end

  # Run allocation if the sale is finalized and price is changed
  before_save :allocate_sale, if: :finalized
  def allocate_sale
    CustomAllocationJob.perform_later(id) if finalized && final_price_changed?
  end

  def active?
    start_date <= Time.zone.today && end_date >= Time.zone.today
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
    ["Buyer", "Offer Template", "Seller"]
  end

  def signature_labels
    ["Buyer Signatory", "Seller Signatory", "Other"]
  end

  def buyer_investors
    investor_list = []
    access_rights.where("access_rights.metadata=?", "Buyer").includes(:investor).find_each do |ar|
      investor_list += ar.investors
    end
    investor_list.uniq
  end

  def offers_by_funding_round
    offers.joins(holding: :funding_round).group("funding_rounds.name").sum(:quantity).sort.to_h
  end

  def display_quantity
    self.show_quantity == "Indicative" ? indicative_quantity : total_offered_quantity
  end

  def display_price
    self.price_type == "Fixed Price" ? final_price.to_s : "#{min_price} - #{max_price}"
  end

  def display_amounts
    self.price_type == "Fixed Price" ? [Money.new(display_quantity * final_price, entity.currency)] : [Money.new(display_quantity * min_price * 100, entity.currency), Money.new(display_quantity * max_price * 100, entity.currency)]
  end
end
