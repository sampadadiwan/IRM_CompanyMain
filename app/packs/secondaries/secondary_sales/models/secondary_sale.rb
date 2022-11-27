class SecondarySale < ApplicationRecord
  include Trackable
  include ActivityTrackable
  include WithFolder
  include SecondarySaleNotifiers
  include SaleAccessScopes

  # Make all models searchable
  update_index('secondary_sale') { self }

  SALE_TYPES = %w[Regular Tranche].freeze

  # buyer_signature_types & seller_signature_types can be set to image,adhar,dsc

  belongs_to :entity

  include FileUploader::Attachment(:spa)

  has_many :documents, as: :owner, dependent: :destroy
  accepts_nested_attributes_for :documents, allow_destroy: true

  has_many :offers, dependent: :destroy
  has_many :interests, dependent: :destroy
  has_many :access_rights, as: :owner, dependent: :destroy
  has_many :fees, as: :owner, dependent: :destroy

  # Customize form for Sale
  belongs_to :form_type, optional: true
  serialize :properties, Hash
  serialize :cmf_allocation_percentage, Hash

  monetize :total_offered_amount_cents, :total_interest_amount_cents,
           :allocation_offer_amount_cents, :allocation_interest_amount_cents,
           with_currency: ->(s) { s.entity.currency }

  validates :name, :start_date, :end_date, :percent_allowed, presence: true
  validates :final_price, numericality: { greater_than: 0 },
                          if: -> { price_type == 'Fixed Price' || finalized }
  validates :final_price, presence: true, if: -> { price_type == 'Fixed Price' }
  validates :min_price, :max_price, presence: true, if: -> { price_type == 'Price Range' }
  validates :max_price, numericality: { greater_than: :min_price }, if: -> { price_type == 'Price Range' }

  scope :for, lambda { |user|
                if user.entity && user.entity.is_holdings_entity
                  # Employees dont need InvestorAccess, they have default access
                  joins(:access_rights)
                    .merge(AccessRight.access_filter)
                    .joins(entity: :investors)
                    # Ensure that the user is an investor and tis investor has been given access rights
                    .where("investors.investor_entity_id=?", user.entity_id)

                else
                  joins(:access_rights)
                    .merge(AccessRight.access_filter)
                    .joins(entity: :investors)
                    # Ensure that the user is an investor and tis investor has been given access rights
                    .where("investors.investor_entity_id=?", user.entity_id)
                    # Ensure this user has investor access
                    .joins(entity: :investor_accesses)
                    .merge(InvestorAccess.approved_for_user(user))

                end
              }

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
    "/Secondary Sales/#{name}-#{id}"
  end

  def setup_folder_details
    setup_folder_from_path(folder_path)
  end

  def document_tags
    %w[Buyer Seller]
  end

  def buyer_investors
    investor_list = []
    access_rights.where("access_rights.metadata=?", "Buyer").includes(:investor).find_each do |ar|
      investor_list += ar.investors
    end
    investor_list.uniq
  end

  # def buyer?(user)
  #   SecondarySale.for(user).where("access_rights.metadata=?", "Buyer").where(id:).present?
  # end

  # def seller?(user)
  #   SecondarySale.for(user).where("access_rights.metadata=?", "Seller").where(id:).present?
  # end

  # def advisor?(user)
  #   user.curr_role == :advisor &&
  #     SecondarySale.for(user).where("access_rights.metadata=?", "Advisor").where(id:).present?
  # end

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
    self.price_type == "Fixed Price" ? [Money.new(display_quantity * final_price, entity.currency)] : [Money.new(display_quantity * min_price, entity.currency), Money.new(display_quantity * max_price, entity.currency)]
  end

  def investor_users(metadata)
    User.joins(investor_accesses: :investor).where("investor_accesses.approved=? and investor_accesses.entity_id=?", true, entity_id).merge(Investor.owner_access_rights(self, metadata))
  end

  def employee_users(metadata)
    User.joins(entity: :investees).where("investors.is_holdings_entity=? and investors.entity_id=?", true, entity_id).merge(Investor.owner_access_rights(self, metadata))
  end
end
