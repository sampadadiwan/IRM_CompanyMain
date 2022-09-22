# == Schema Information
#
# Table name: excercises
#
#  id             :integer          not null, primary key
#  entity_id      :integer          not null
#  holding_id     :integer          not null
#  user_id        :integer          not null
#  option_pool_id :integer          not null
#  quantity       :integer          default("0")
#  price_cents    :decimal(20, 2)   default("0.00")
#  amount_cents   :decimal(20, 2)   default("0.00")
#  tax_cents      :decimal(20, 2)   default("0.00")
#  approved       :boolean          default("0")
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  tax_rate       :decimal(5, 2)    default("0.00")
#  approved_on    :date
#

class Excercise < ApplicationRecord
  audited

  update_index('entity') { self }

  belongs_to :entity
  belongs_to :holding
  has_one :created_holding, foreign_key: :created_from_excercise_id, class_name: "Holding", dependent: :destroy
  belongs_to :user
  belongs_to :option_pool

  has_many_attached :payment_proof, service: :amazon

  monetize :price_cents, :amount_cents, with_currency: ->(e) { e.entity.currency }

  counter_culture :option_pool,
                  column_name: proc { |e| e.approved ? 'excercised_quantity' : nil },
                  delta_column: 'quantity'

  counter_culture :holding,
                  column_name: proc { |e| e.approved ? 'excercised_quantity' : nil },
                  delta_column: 'quantity'

  validates :quantity, :price, :amount, presence: true
  validates :quantity, :price, :amount, numericality: { greater_than: 0 }
  validates :payment_proof, presence: true, on: :create unless Rails.env.test?
  validate :lapsed_holding, on: :create
  validate :validate_quantity, on: :update

  scope :approved, -> { where(approved: true) }
  scope :not_approved, -> { where(approved: false) }

  before_save :compute
  after_create :notify_excercise

  def compute
    self.amount_cents = quantity * price_cents
  end

  def lapsed_holding
    # errors.add(:holding, "can't be lapsed") if holding.lapsed
    errors.add(:quantity, "can't be greater than #{holding.net_avail_to_excercise_quantity}") if quantity > holding.net_avail_to_excercise_quantity
  end

  def validate_quantity
    errors.add(:quantity, "can't be greater than #{allowed}") if quantity > holding.net_avail_to_excercise_quantity
  end

  def notify_excercise
    ExcerciseMailer.with(excercise_id: id).notify_excercise.deliver_later
  end
end
