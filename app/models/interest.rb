# == Schema Information
#
# Table name: interests
#
#  id                      :integer          not null, primary key
#  entity_id         :integer
#  quantity                :integer
#  price                   :decimal(10, )
#  user_id                 :integer          not null
#  interest_entity_id      :integer
#  secondary_sale_id       :integer          not null
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  short_listed            :boolean          default("0")
#  escrow_deposited        :boolean          default("0")
#  final_price             :decimal(10, 2)   default("0.00")
#  amount_cents            :decimal(20, 2)   default("0.00")
#  allocation_quantity     :integer          default("0")
#  allocation_amount_cents :decimal(20, 2)   default("0.00")
#  allocation_percentage   :decimal(5, 2)    default("0.00")
#

class Interest < ApplicationRecord
  belongs_to :user
  belongs_to :secondary_sale
  belongs_to :interest_entity, class_name: "Entity"
  belongs_to :entity, class_name: "Entity"
  has_many :offers, dependent: :destroy
  has_many :tasks, as: :owner, dependent: :destroy
  has_many :messages, as: :owner, dependent: :destroy

  has_one_attached  :spa, service: :amazon
  has_many_attached :buyer_docs, service: :amazon

  # Customize form
  belongs_to :form_type, optional: true
  serialize :properties, Hash

  validates :quantity, comparison: { less_than_or_equal_to: :total_offered_quantity }
  validates :price, comparison: { less_than_or_equal_to: :max_price } if proc { |i| i.secondary_sale.max_price }
  validates :price, comparison: { greater_than_or_equal_to: :min_price }

  delegate :total_offered_quantity, to: :secondary_sale
  delegate :min_price, to: :secondary_sale
  delegate :max_price, to: :secondary_sale
  delegate :email, to: :user, prefix: true

  scope :short_listed, -> { where(short_listed: true) }
  scope :escrow_deposited, -> { where(escrow_deposited: true) }
  scope :priced_above, ->(price) { where("price >= ?", price) }
  scope :eligible, ->(secondary_sale) { short_listed.priced_above(secondary_sale.final_price) }

  before_validation :set_defaults

  validates :quantity, :price, presence: true
  validates :buyer_entity_name, :address, :PAN, :contact_name, :email, presence: true, if: proc { |i| i.secondary_sale.finalized }

  before_save :notify_shortlist, if: :short_listed
  before_save :notify_finalized, if: :finalized
  after_create :notify_interest

  monetize :amount_cents, :allocation_amount_cents, with_currency: ->(i) { i.entity.currency }

  counter_culture :secondary_sale,
                  column_name: proc { |o| o.short_listed ? 'total_interest_quantity' : nil },
                  delta_column: 'quantity'

  counter_culture :secondary_sale,
                  column_name: proc { |o| o.short_listed ? 'total_interest_amount_cents' : nil },
                  delta_column: 'amount_cents'

  def notify_interest
    InterestMailer.with(interest_id: id).notify_interest.deliver_later
  end

  def notify_shortlist
    InterestMailer.with(interest_id: id).notify_shortlist.deliver_later if short_listed_changed?
  end

  def notify_finalized
    InterestMailer.with(interest_id: id).notify_finalized.deliver_later if finalized_changed?
  end

  def set_defaults
    self.interest_entity_id ||= user.entity_id
    self.entity_id ||= secondary_sale.entity_id
    self.amount_cents = quantity * final_price * 100 if final_price.positive?
    self.allocation_amount_cents = allocation_quantity * final_price * 100 if final_price.positive?
  end

  def allocation_delta
    allocation_quantity - offer_quantity
  end
end
