class Investment < ApplicationRecord
  audited
  include Trackable
  include InvestmentScopes
  include InvestmentCounters
  # Make all models searchable
  update_index('investment') { self if index_record? }

  # "Equity,Preferred,Debt,Options"
  INSTRUMENT_TYPES = ENV["INSTRUMENT_TYPES"].split(",")

  # "Lead Investor,Co-Investor,Founder,Individual,Employee"
  INVESTOR_CATEGORIES = ENV["INVESTOR_CATEGORIES"].split(",")

  belongs_to :investor
  delegate :investor_entity_id, to: :investor
  delegate :investor_name, to: :investor

  belongs_to :funding_round
  delegate :name, to: :funding_round, prefix: :funding_round

  belongs_to :aggregate_investment, optional: true

  belongs_to :entity, touch: true
  delegate :name, to: :entity, prefix: :investee

  has_many :holdings, dependent: :destroy
  validates :investment_date, :quantity, :investment_instrument, :price, presence: true
  validates :investment_type, :investor_type, :investment_instrument, :category, length: { maximum: 100 }
  validates :status, length: { maximum: 20 }
  validates :currency, length: { maximum: 10 }
  validates :units, length: { maximum: 15 }
  validates :spv, :anti_dilution, length: { maximum: 50 }
  validates :liq_pref_type, length: { maximum: 25 }

  validate :validate_option_pool, if: -> { investment_instrument == 'Options' }

  # Handled by money-rails gem
  monetize :amount_cents, :price_cents, with_model_currency: :currency

  def self.INVESTOR_CATEGORIES(entity = nil)
    entity && entity.investor_categories.present? ? entity.investor_categories.split(",").map(&:strip) : INVESTOR_CATEGORIES
  end

  def self.INSTRUMENT_TYPES(entity = nil)
    entity && entity.instrument_types.present? ? entity.instrument_types.split(",").map(&:strip) : INSTRUMENT_TYPES
  end

  def validate_option_pool
    errors.add(:funding_round, "Funding round #{funding_round.name} not associated with Option Pool") if funding_round.option_pool.nil?
  end

  def to_s
    investor.investor_name
  end

  before_save :update_defaults

  def update_defaults
    if investor.is_holdings_entity
      # This is because each holding has a quantity, price and a value
      # The quantity and value is added to the investment
      # So we compute the avg price
      self.price = amount / quantity if quantity.positive?
    else
      self.amount = quantity * price
    end
    self.currency = entity.currency
    self.investment_type = funding_round.name
    self.investment_instrument = investment_instrument.strip
    self.employee_holdings = true if investment_type == "Employee Holdings"

    # pull this from the funding round if not set.
    self.anti_dilution ||= funding_round.anti_dilution
    self.liq_pref_type ||= funding_round.liq_pref_type
    self.preferred_conversion ||= 1
    self.preferred_converted_qty = quantity * self.preferred_conversion
  end

  def self.for_investor_all(current_user)
    Investment
      # Ensure the access rights for Investment
      .joins(:investor)
      # .merge(AccessRight.access_filter(current_user))
      # Ensure that the user is an investor and tis investor has been given access rights
      .where("investors.investor_entity_id=?", current_user.entity_id)
      # Ensure this user has investor access
      .joins(entity: :investor_accesses)
      .merge(InvestorAccess.approved_for_user(current_user))
  end

  def self.for_investor(current_user, entity)
    investments = entity.investments
                        # Ensure the access rights for Investment
                        .joins(entity: %i[investors access_rights])
                        .merge(AccessRight.access_filter(current_user))
                        # Ensure that the user is an investor and tis investor has been given access rights
                        .where("entities.id=?", entity.id)
                        .where("investors.investor_entity_id=?", current_user.entity_id)
                        # Ensure this user has investor access
                        .joins(entity: :investor_accesses)
                        .merge(InvestorAccess.approved_for_user(current_user))

    # return investments if investments.blank?

    # Is this user from an investor
    investor = Investor.for(current_user, entity).first

    # Get the investor access for this user and this entity
    access_right = AccessRight.investments.investor_access(investor, current_user).last
    return Investment.none if access_right.nil?

    Rails.logger.debug access_right.to_json

    case access_right.metadata
    when AccessRight::ALL
      # Do nothing - we got all the investments
      logger.debug "Access to investor #{current_user.email} to ALL Entity #{entity.id} investments"
    when AccessRight::SELF
      # Got all the investments for this investor
      logger.debug "Access to investor #{current_user.email} to SELF Entity #{entity.id} investments"
      investments = investments.where(investor_id: investor.id)
    end

    investments
  end

  def self.write_xl(entity_id)
    investments = Investment.where(entity_id:).includes(:funding_round, :investor)
    open_book = Spreadsheet.open('scenarios.xls')
    new_row_index = 37

    header = ["Category", "Funding Round", "Investor", "Instrument", "Investment Date", "Quantity", "Percentage",
              "Fully Diluted", "Price", "Amount", "Liquidation Pref", "Liq Pref Type", "Anti Dilution"]
    open_book.worksheet(0).row(new_row_index).concat header

    investments.each do |inv|
      new_row_index += 1
      open_book.worksheet(0).row(new_row_index).push inv.category, inv.funding_round.name,
                                                     inv.investor.investor_name,
                                                     inv.investment_instrument, inv.investment_date, inv.quantity, inv.percentage_holding,
                                                     inv.diluted_percentage, inv.price.to_s.to_f,
                                                     inv.amount.to_s.to_f, inv.liquidation_preference, inv.liq_pref_type, inv.anti_dilution

      Rails.logger.debug { "Wrote row #{new_row_index}" }
    end

    open_book.write('test_new.xls')

    nil
  end
end
