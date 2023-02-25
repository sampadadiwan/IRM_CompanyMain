class CapitalCall < ApplicationRecord
  include WithCustomField
  include WithFolder
  include Trackable
  include ActivityTrackable
  tracked owner: proc { |_controller, model| model.fund }, entity_id: proc { |_controller, model| model.entity_id }

  include ForInvestor

  belongs_to :entity
  belongs_to :fund, touch: true

  belongs_to :approved_by_user, class_name: "User", optional: true
  # Stores the prices for unit types for this call
  serialize :unit_prices, Hash
  serialize :fund_closes, Array

  has_many :capital_remittances, dependent: :destroy

  validates :name, :due_date, :call_date, :percentage_called, :fund_closes, presence: true
  validates :percentage_called, numericality: { in: 0..100 }

  monetize :call_amount_cents, :collected_amount_cents, with_currency: ->(i) { i.fund.currency }
  counter_culture :fund, column_name: 'call_amount_cents', delta_column: 'call_amount_cents'

  before_save :compute_call_amount
  def compute_call_amount
    self.call_amount_cents = fund.committed_amount_cents * percentage_called / 100.0
  end

  after_commit :generate_capital_remittances
  def generate_capital_remittances
    CapitalCallJob.set.perform_later(id, "Generate") if generate_remittances && saved_change_to_percentage_called?
  end

  after_commit :send_notification, if: :approved
  def send_notification
    CapitalCallJob.perform_later(id, "Notify") if !manual_generation && saved_change_to_approved?
  end

  def folder_path
    "#{fund.folder_path}/Capital Calls/#{name.delete('/')}"
  end

  def to_s
    "#{name}, #{percentage_called}%"
  end

  def due_amount
    call_amount - collected_amount
  end

  def percentage_raised
    call_amount_cents.positive? ? (collected_amount_cents * 100.0 / call_amount_cents).round(6) : 0
  end

  def notify_capital_call
    FundMailer.with(id:).notify_capital_call.deliver_later
  end

  def reminder_capital_call
    FundMailer.with(id:).reminder_capital_call.deliver_later
  end
end
