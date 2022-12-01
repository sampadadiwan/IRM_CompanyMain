class Excercise < ApplicationRecord
  audited
  include WithFolder

  update_index('entity') { self }

  belongs_to :entity
  belongs_to :holding
  has_one :created_holding, foreign_key: :created_from_excercise_id, class_name: "Holding", dependent: :destroy
  belongs_to :user
  belongs_to :option_pool

  has_many :documents, as: :owner, dependent: :destroy
  accepts_nested_attributes_for :documents, allow_destroy: true

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
  validates :payment_proof, presence: true, on: :create unless Rails.env.test?
  validate :lapsed_holding, on: :create
  validate :validate_quantity, on: :update

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
    errors.add(:quantity, "can't be greater than #{allowed}") if quantity > holding.net_avail_to_excercise_quantity
  end

  def notify_excercise
    ExcerciseMailer.with(excercise_id: id).notify_excercise.deliver_later
  end

  def folder_path
    "#{option_pool.folder_path}/Excercises/#{user.full_name}-#{id}"
  end
end
