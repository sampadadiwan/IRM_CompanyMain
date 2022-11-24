class Holding < ApplicationRecord
  audited
  include HoldingCounters
  include HoldingScopes
  include OptionCalculations

  OPTION_TYPES = ["Regular", "Phantom", "Equity SAR"].freeze

  update_index('holding') { self }

  belongs_to :user, optional: true
  belongs_to :entity

  belongs_to :funding_round, optional: true

  belongs_to :investor
  # This is only for options
  belongs_to :option_pool, optional: true, touch: true

  has_many :offers, dependent: :destroy
  has_many :excercises, dependent: :destroy

  # The Investment to which this is linked
  belongs_to :investment, optional: true
  # If this holding was crated by excercising an option
  belongs_to :created_from_excercise, class_name: "Excercise", optional: true
  has_one :aggregated_investment, through: :investment
  has_rich_text :note

  include FileUploader::Attachment(:grant_letter)

  # Customize form
  belongs_to :form_type, optional: true
  serialize :properties, Hash

  monetize :price_cents, :value_cents, with_currency: ->(i) { i.entity.currency }

  validates :funding_round, :investment_instrument, :quantity, :holding_type, presence: true
  validate :allocation_allowed, if: -> { investment_instrument == 'Options' }
  validates :vested_quantity, numericality: { less_than_or_equal_to: :orig_grant_quantity }
  validates :vested_quantity, numericality: { greater_than_or_equal_to: :excercised_quantity }

  def allocation_allowed
    errors.add(:option_pool, "Option pool required") if option_pool.nil?
    if option_pool
      if new_record?
        errors.add(:option_pool, "Insufficiant available quantity in Option pool #{option_pool.name}. #{option_pool.available_quantity} < #{quantity}") if option_pool.available_quantity < quantity
      elsif option_pool.available_quantity < (quantity - quantity_was)
        errors.add(:option_pool, "Insufficiant available quantity in Option pool #{option_pool.name}. #{option_pool.available_quantity} < #{quantity} - #{quantity_was}")
      end
    end
  end

  delegate :active_secondary_sale, to: :entity

  def holder_name
    user ? user.full_name : investor.investor_name
  end

  def notify_approval
    HoldingMailer.with(holding_id: id).notify_approval.deliver_later
  end

  def notify_cancellation
    HoldingMailer.with(holding_id: id).notify_cancellation.deliver_later
  end

  def notify_lapsed
    HoldingMailer.with(holding_id: id).notify_lapsed.deliver_later
  end

  def notify_lapse_upcoming
    HoldingMailer.with(holding_id: id).notify_lapse_upcoming.deliver_later
  end

  before_save :update_quantity
  before_save :update_option_dilutes, if: -> { investment_instrument == 'Options' }

  def update_quantity
    if investment_instrument == 'Options'
      update_option_quantity
    else
      self.quantity = orig_grant_quantity - sold_quantity
    end

    self.grant_date ||= Time.zone.today
    self.value_cents = quantity * price_cents
  end

  def display_status
    if cancelled
      if cancelled_quantity == orig_grant_quantity
        "Cancelled"
      else
        "Partial Cancel"
      end
    elsif approved
      "Approved"
    end
  end
end
