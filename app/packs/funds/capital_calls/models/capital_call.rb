class CapitalCall < ApplicationRecord
  include WithCustomField
  include WithFolder
  include Trackable.new

  include RansackerAmounts.new(fields: %w[call_amount collected_amount capital_fees other_fees])
  include WithCustomNotifications

  include ForInvestor

  FEE_TYPES = ["Fees Part Of Capital", "Other Fees"].freeze
  CALL_BASIS = ["Percentage of Commitment", "Upload", "Investable Capital Percentage"].freeze

  belongs_to :entity
  belongs_to :fund, touch: true

  belongs_to :approved_by_user, class_name: "User", optional: true
  # Stores the prices for unit types for this call
  serialize :unit_prices, type: Hash
  serialize :close_percentages, type: Hash
  serialize :fund_closes, type: Array

  has_many :capital_remittances, dependent: :destroy
  has_many :remittance_documents, through: :capital_remittances, source: :documents, class_name: "Document"

  # This is the list of call_fees to be pulled out of account entries for the folio
  has_many :call_fees, dependent: :destroy
  accepts_nested_attributes_for :call_fees, allow_destroy: true
  # This stores any formulas selected by the user, to be used for call_fee computation for the folio
  serialize :fee_formula_ids, type: Array

  validates_uniqueness_of :name, scope: :fund_id
  normalizes :name, with: ->(name) { name.strip.squeeze(" ") }
  validates :name, :due_date, :call_date, :percentage_called, presence: true
  validates :fund_closes, presence: true, unless: -> { call_basis == 'Upload' }
  # validates percentage_called is less than or equal to 100
  validates :percentage_called, numericality: { less_than_or_equal_to: 100 }
  validates :name, :fund_closes, length: { maximum: 255 }

  monetize :call_amount_cents, :amount_to_be_called_cents, :capital_fee_cents, :other_fee_cents, :collected_amount_cents, with_currency: ->(i) { i.fund.currency }

  # This is a list of commitments for which this call is applicable
  def applicable_to
    commitments = fund.capital_commitments

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
    when "Upload"
      self.percentage_called = 0
      self.amount_to_be_called_cents = 0
    else
      self.percentage_called = 0
    end

    self.generate_remittances = true if call_basis != "Upload"
  end

  def generate_capital_remittances(later: true)
    if call_basis != "Upload" && generate_remittances &&
       (saved_change_to_percentage_called? || saved_change_to_amount_to_be_called_cents? || saved_change_to_fund_closes?)
      if later
        CapitalCallJob.perform_later(id, "Generate")
      else
        CapitalCallJob.perform_now(id, "Generate")
      end
    end
  end

  def send_notification
    CapitalCallJob.perform_later(id, "Notify") if send_call_notice_flag && !manual_generation && saved_change_to_approved?
  end

  def folder_path
    "#{fund.folder_path}/Capital Calls/#{name.delete('/')}"
  end

  delegate :to_s, to: :name

  def due_amount
    call_amount + other_fee - collected_amount
  end

  def percentage_raised
    call_amount_cents.positive? ? (collected_amount_cents * 100.0 / call_amount_cents).round(6) : 0
  end

  def notify_capital_call
    capital_remittances.pending.each do |cr|
      cr.investor.notification_users(fund).each do |user|
        CapitalRemittanceNotifier.with(record: cr, entity_id:, email_method: :notify_capital_remittance, msg: "Capital Call: #{fund.name}").deliver_later(user)
      end
    end
  end

  def reminder_capital_call
    capital_remittances.where(status: %w[Pending Overdue]).find_each do |cr|
      cr.investor.notification_users(fund).each do |user|
        CapitalRemittanceNotifier.with(record: cr, entity_id:, email_method: :reminder_capital_remittance, msg: "Capital Call Reminder: #{fund.name}").deliver_later(user)
      end
    end
  end

  def fund_units
    FundUnit.where(fund_id:, owner_type: "CapitalRemittance", owner_id: capital_remittance_ids)
  end

  def fee_account_entry_names
    fund.account_entries.where("name like '%Fee%' or name like '%Expense%'").pluck(:name).uniq << "Other"
  end

  def call_basis_list
    if entity.entity_setting.call_basis.present?
      CALL_BASIS + entity.entity_setting.call_basis.split(",")
    else
      CALL_BASIS
    end
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[name due_date approved call_date status verified call_amount collected_amount capital_fees other_fees percentage_called].sort
  end

  def self.ransackable_associations(_auth_object = nil)
    ["fund"]
  end

  def fee_formulas
    fee_formula_ids.present? ? CallFee.where(id: fee_formula_ids) : CallFee.none
  end

  def all_call_fees
    call_fees + fee_formulas
  end
end
