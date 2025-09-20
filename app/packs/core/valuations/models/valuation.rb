class Valuation < ApplicationRecord
  include Trackable.new
  include WithCustomField
  include WithExchangeRate

  include RansackerAmounts.new(fields: %w[per_share_value])

  STANDARD_COLUMNS = {
    "Name" => "name",
    "Valuation Date" => "valuation_date",
    "Per Share Value" => "per_share_value",
    "Currency" => "currency"
  }.freeze

  ADDITIONAL_COLUMNS_FROM = ["investment_instrument"].freeze

  belongs_to :entity
  belongs_to :owner, polymorphic: true, optional: true, touch: true
  belongs_to :investment_instrument # , optional: true
  include FileUploader::Attachment(:report)

  monetize :valuation_cents, :per_share_value_cents,
           with_currency: ->(s) { s.currency }

  scope :by_instrument, lambda { |instrument_name|
    joins(:investment_instrument).where(investment_instrument: { name: instrument_name })
  }

  scope :for_portfolio_companies, lambda {
    joins("INNER JOIN investors ON valuations.owner_id = investors.id AND valuations.owner_type = 'Investor'")
  }

  # Ransacker to search by investor name
  ransacker :portfolio_company_name do |_parent|
    # Only works when owner_type is 'Investor'
    Arel.sql <<-SQL.squish
      (
        CASE
          WHEN valuations.owner_type = 'Investor'
          THEN (
            SELECT investors.investor_name
            FROM investors
            WHERE investors.id = valuations.owner_id
            LIMIT 1
          )
        END
      )
    SQL
  end

  default_scope { where(synthetic: false) }

  # return all, but keep other default conditions (e.g., deleted_at: nil)
  scope :with_synthetic, -> { unscope(where: :synthetic) }

  # Validations
  validates :per_share_value, numericality: { greater_than_or_equal_to: 0 }
  validates :valuation_date, presence: true
  validates :valuation_date, uniqueness: { scope: %i[investment_instrument_id entity_id owner_id owner_type] }
  validates :name, length: { maximum: 60 }, allow_blank: true

  # Ensure callback to the owner
  after_save :update_owner
  after_save :update_entity
  def update_entity
    if owner_type.blank?
      entity.per_share_value_cents = per_share_value_cents
      entity.save
    end
  end

  def update_owner
    if ((!synthetic && saved_change_to_valuation_cents?) ||
       saved_change_to_per_share_value_cents? ||
       saved_change_to_valuation_date?) && owner.respond_to?(:valuation_updated) && latest?
      owner.valuation_updated(self)
    end
  end

  before_save :set_name
  def set_name
    if investment_instrument.present?
      self.name = "#{investment_instrument} - #{valuation_date}" if name.blank?
    elsif name.blank?
      self.name = "#{entity} - #{valuation_date}"
    end
  end

  # Check if this is the latest valuation
  # TODO - move to an attribute
  def latest?
    if synthetic
      false
    elsif owner.present?
      investment_instrument.valuations.where(owner: owner).where("valuation_date > ?", valuation_date).empty?
    else
      investment_instrument.valuations.where("valuation_date > ?", valuation_date).empty?
    end
  end

  def to_s
    name
  end

  def to_extended_s
    if synthetic
      "#{owner} - #{investment_instrument} - #{valuation_date} (Synthetic)"
    else
      "#{owner} - #{investment_instrument} - #{valuation_date}"
    end
  end

  def currency
    if investment_instrument
      investment_instrument.currency
    elsif owner.respond_to?(:currency) && owner.currency.present?
      owner.currency
    else
      entity.currency
    end
  end

  def per_share_value_in(to_currency, as_of)
    convert_currency(currency, to_currency, per_share_value_cents, as_of)
  end

  # This method is used to add custom fields to the Valuation form, to enable value bridge
  def self.add_value_bridge_custom_fields(entity)
    fields = [
      ["net_debt", "", "NumberField"],
      ["revenue", "", "NumberField"],
      ["ebitda_margin", "", "NumberField"],
      ["ebitda", "json_fields[\"revenue\"].to_f *  json_fields[\"ebitda_margin\"].to_f / 100", "Calculation"],
      ["valuation_multiple", "", "NumberField"],
      ["enterprise_value", "json_fields[\"ebitda\"].to_f * json_fields[\"valuation_multiple\"].to_f", "Calculation"],
      ["equity_value", "json_fields[\"enterprise_value\"].to_f  - json_fields[\"net_debt\"].to_f", "Calculation"],
      ["debt_ratio", "(json_fields[\"net_debt\"].to_f  / json_fields[\"enterprise_value\"].to_f).round(2)", "Calculation"],
      ["equity_ratio", "( json_fields[\"equity_value\"].to_f  / json_fields[\"enterprise_value\"].to_f).round(2)", "Calculation"]
    ]

    ft = entity.form_types.where(name: "Valuation").first
    ft ||= entity.form_types.create(name: "Valuation", entity: entity)

    fields.each do |field|
      ft.form_custom_fields.create(name: field[0], meta_data: field[1], field_type: field[2])
    end
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[portfolio_company_name per_share_value owner_id owner_type synthetic valuation_date].sort
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[investment_instrument]
  end
end
