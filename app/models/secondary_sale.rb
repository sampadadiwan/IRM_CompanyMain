# == Schema Information
#
# Table name: secondary_sales
#
#  id                               :integer          not null, primary key
#  name                             :string(255)
#  entity_id                        :integer          not null
#  start_date                       :date
#  end_date                         :date
#  percent_allowed                  :integer          default("0")
#  min_price                        :decimal(20, 2)
#  max_price                        :decimal(20, 2)
#  active                           :boolean          default("1")
#  created_at                       :datetime         not null
#  updated_at                       :datetime         not null
#  total_offered_quantity           :integer          default("0")
#  visible_externally               :boolean          default("0")
#  deleted_at                       :datetime
#  final_price                      :decimal(10, 2)   default("0.00")
#  total_offered_amount_cents       :decimal(20, 2)   default("0.00")
#  total_interest_amount_cents      :decimal(20, 2)   default("0.00")
#  total_interest_quantity          :integer          default("0")
#  offer_allocation_quantity        :integer          default("0")
#  interest_allocation_quantity     :integer          default("0")
#  allocation_percentage            :decimal(7, 4)    default("0.0000")
#  allocation_offer_amount_cents    :decimal(20, 2)   default("0.00")
#  allocation_interest_amount_cents :decimal(20, 2)   default("0.00")
#  allocation_status                :string(10)
#  price_type                       :string(15)
#  finalized                        :boolean          default("0")
#  seller_doc_list                  :text(65535)
#  seller_transaction_fees_pct      :decimal(5, 2)
#  properties                       :text(65535)
#  form_type_id                     :integer
#  lock_allocations                 :boolean          default("0")
#

class SecondarySale < ApplicationRecord
  include Trackable
  include ActivityTrackable
  include WithFolder
  include SecondarySaleNotifiers

  # Make all models searchable
  update_index('secondary_sale') { self }

  SALE_TYPES = %w[Regular Tranche].freeze

  belongs_to :entity

  has_one_attached :final_allocation, service: :amazon
  has_one_attached :spa, service: :amazon

  has_many :documents, as: :owner, dependent: :destroy
  accepts_nested_attributes_for :documents, allow_destroy: true

  has_many :offers, dependent: :destroy
  has_many :interests, dependent: :destroy
  has_many :access_rights, as: :owner, dependent: :destroy

  # Customize form for Sale
  belongs_to :form_type, optional: true
  serialize :properties, Hash

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
                joins(:access_rights)
                  .merge(AccessRight.access_filter)
                  .joins(entity: :investors)
                  # Ensure that the user is an investor and tis investor has been given access rights
                  .where("investors.investor_entity_id=?", user.entity_id)
                  # Ensure this user has investor access
                  .joins(entity: :investor_accesses)
                  .merge(InvestorAccess.approved_for_user(user))
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
    AllocationJob.perform_later(id) if finalized && final_price_changed?
  end

  def self.for_investor(user, entity)
    SecondarySale
      # Ensure the access rghts for Document
      .joins(:access_rights)
      .merge(AccessRight.access_filter)
      .joins(entity: :investors)
      # Ensure that the user is an investor and tis investor has been given access rights
      .where("entities.id=?", entity.id)
      .where("investors.investor_entity_id=?", user.entity_id)
      # Ensure this user has investor access
      .joins(entity: :investor_accesses)
      .merge(InvestorAccess.approved_for_user(user))
      .distinct
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

  def setup_folder_details
    parent_folder = Folder.where(entity_id:, level: 1, name: self.class.name.pluralize.titleize).first
    setup_folder(parent_folder, name, %w[Offers Interests])
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

  def buyer?(user)
    SecondarySale.for(user).where("access_rights.metadata=?", "Buyer").where(id:).present?
  end

  def seller?(user)
    SecondarySale.for(user).where("access_rights.metadata=?", "Seller").where(id:).present?
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
    self.price_type == "Fixed Price" ? [Money.new(display_quantity * final_price, entity.currency)] : [Money.new(display_quantity * min_price, entity.currency), Money.new(display_quantity * max_price, entity.currency)]
  end
end
