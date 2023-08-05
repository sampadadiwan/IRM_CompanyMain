class CapitalCall < ApplicationRecord
  include WithCustomField
  include WithFolder
  include Trackable
  include ActivityTrackable
  tracked owner: proc { |_controller, model| model.fund }, entity_id: proc { |_controller, model| model.entity_id }

  include ForInvestor

  FEE_TYPES = ["Fees Part Of Capital", "Other Fees"].freeze
  CALL_BASIS = ["Percentage of Commitment", "Amount allocated on Investable Capital", "Upload"].freeze

  enum :commitment_type, { Pool: "Pool", CoInvest: "CoInvest" }
  scope :pool, -> { where(commitment_type: 'Pool') }
  scope :co_invest, -> { where(commitment_type: 'CoInvest') }

  belongs_to :entity
  belongs_to :fund, touch: true
  has_many :notifications, as: :recipient, dependent: :destroy

  belongs_to :approved_by_user, class_name: "User", optional: true
  # Stores the prices for unit types for this call
  serialize :unit_prices, Hash
  serialize :fund_closes, Array

  has_many :call_fees, dependent: :destroy
  accepts_nested_attributes_for :call_fees, allow_destroy: true

  has_many :capital_remittances, dependent: :destroy
  validates_uniqueness_of :name, scope: :fund_id
  validates :name, :due_date, :call_date, :percentage_called, :fund_closes, :commitment_type, presence: true
  # validates :percentage_called, numericality: { in: 0..100 }

  monetize :call_amount_cents, :amount_to_be_called_cents, :capital_fee_cents, :other_fee_cents, :collected_amount_cents, with_currency: ->(i) { i.fund.currency }

  validates :commitment_type, length: { maximum: 10 }
  validates :name, :fund_closes, length: { maximum: 255 }
  # This is a list of commitments for which this call is applicable
  def applicable_to
    commitments = Pool? ? fund.capital_commitments.pool : fund.capital_commitments.co_invest

    # The call is applicable only to those commitments which have a fund_close specified in the call
    if fund_closes.nil? || fund_closes.include?("All")
      commitments
    else
      commitments.where(fund_close: fund_closes)
    end
  end

  before_save :setup_defaults
  def setup_defaults
    case call_basis
    when "Percentage of Commitment"
      self.amount_to_be_called_cents = 0
    when "Amount allocated on Investable Capital"
      self.percentage_called = 0
    when "Upload"
      self.percentage_called = 0
      self.amount_to_be_called_cents = 0
    end

    self.generate_remittances = true if call_basis != "Upload"
  end

  after_commit :generate_capital_remittances
  def generate_capital_remittances
    CapitalCallJob.perform_later(id, "Generate") if generate_remittances && (saved_change_to_percentage_called? || saved_change_to_amount_to_be_called_cents? || saved_change_to_fund_closes?)
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
    call_amount + other_fee - collected_amount
  end

  def percentage_raised
    call_amount_cents.positive? ? (collected_amount_cents * 100.0 / call_amount_cents).round(6) : 0
  end

  def notify_capital_call
    capital_remittances.pending.each do |cr|
      cr.investor.approved_users.each do |user|
        CapitalRemittanceNotification.with(entity_id:, capital_remittance_id: cr.id, email_method: :notify_capital_remittance, msg: "New Capital Call: #{name}").deliver_later(user)
      end
    end
  end

  def reminder_capital_call
    capital_remittances.pending.each do |cr|
      cr.investor.approved_users.each do |user|
        CapitalRemittanceNotification.with(entity_id:, capital_remittance_id: cr.id, email_method: :reminder_capital_remittance, msg: "Reminder for Capital Call: #{name}").deliver_later(user)
      end
    end
  end

  def fund_units
    FundUnit.where(fund_id:, owner_type: "CapitalRemittance", owner_id: capital_remittance_ids)
  end

  def fee_account_entry_names
    fund.account_entries.where("name like '%Fee%' or name like '%Expense%'").pluck(:name).uniq
  end
end
