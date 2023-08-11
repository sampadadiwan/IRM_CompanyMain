class Excercise < ApplicationRecord
  audited
  include Trackable
  include WithFolder

  update_index('entity') { self }

  belongs_to :entity
  belongs_to :holding
  has_one :created_holding, foreign_key: :created_from_excercise_id, class_name: "Holding", dependent: :destroy
  belongs_to :user
  belongs_to :option_pool
  has_many :notifications, as: :recipient, dependent: :destroy

  include FileUploader::Attachment(:payment_proof)

  monetize :price_cents, :amount_cents, with_currency: ->(e) { e.entity.currency }

  counter_culture :holding,
                  column_name: proc { |e| e.approved ? 'excercised_quantity' : nil },
                  delta_column: 'quantity'

  counter_culture :option_pool,
                  column_name: proc { |e| e.approved ? 'excercised_quantity' : nil },
                  delta_column: 'quantity'

  validates :quantity, :price, :amount, presence: true
  validates :quantity, :price, :amount, numericality: { greater_than: 0 }
  validates :payment_proof, presence: true, on: :create, if: proc { |e| !e.cashless && !Rails.env.test? } # unless cashless || Rails.env.test?
  validate :lapsed_holding, on: :create
  validate :validate_quantity, on: :update
  validate :validate_cashless

  def validate_cashless
    errors.add(:cashless, "must be checked to allot or sell shares") if !cashless && (shares_to_allot.present? || shares_to_sell.present?)
  end

  scope :approved, -> { where(approved: true) }
  scope :not_approved, -> { where(approved: false) }

  before_save :compute
  after_create_commit :notify_excercise

  def compute
    self.amount_cents = quantity * price_cents
  end

  def lapsed_holding
    # errors.add(:holding, "can't be lapsed") if holding.lapsed
    errors.add(:quantity, "can't be greater than #{holding.net_avail_to_excercise_quantity}") if quantity > holding.net_avail_to_excercise_quantity
  end

  def validate_quantity
    errors.add(:quantity, "can't be greater than #{holding.net_avail_to_excercise_quantity}") if quantity > holding.net_avail_to_excercise_quantity
  end

  def notify_excercise
    if cashless
      ExcerciseNotification.with(entity_id:, excercise_id: id, email_method: :notify_cashless_excercise, msg: "Cashless Exercise of Option").deliver_later(user)
    else
      ExcerciseNotification.with(entity_id:, excercise_id: id, email_method: :notify_excercise, msg: "Exercise of Option").deliver_later(user)
    end
  end

  def notify_approval
    ExcerciseNotification.with(entity_id:, excercise_id: id, email_method: :notify_approval, msg: "Exercise of Option Approved").deliver_later(user)
  end

  def folder_path
    "#{option_pool.folder_path}/Excercises/#{user.full_name.delete('/')}-#{id}"
  end
end
