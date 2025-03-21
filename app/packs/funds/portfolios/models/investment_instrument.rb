class InvestmentInstrument < ApplicationRecord
  include Trackable.new
  include WithCustomField

  # SECTORS = ENV["SECTORS"].split(",").sort
  # rubocop:disable Layout/SpaceAfterComma
  TYPES_OF_INVESTEE_COMPANY = ["Company","LLP","AIF","REIT","InvIT","Mutual Fund (MF)","Venture Capital Undertaking","Startup","Trust set up by an Asset Reconstruction Company (ARC)","ARC","Micro enterprise","Small enterprise","Medium enterprise","SPV","Social Enterprise"].freeze

  TYPES_OF_SECURITY = ["Listed/Proposed to be listed Equity","Unlisted Equity/Equity Linked","Listed/Proposed to be listed Debt","Unlisted Debt","Listed/Proposed to be listed equity on SME exchange","Others (Listed)","Others (Unlisted)","Units of Mutual Funds","Units of Cat-1 AIFs","Units of Cat-2 AIFs","Units of Cat-3 AIFs","REITs/Invits","G-Sec","LLP Interest","Security Receipts","Securitised Debt","Grants","Special Situation asset as provided in Reg 19I 2(a),(c),CDS"].freeze

  SECTORS = ["Agriculture & Allied activities","Aerospace & Defense","Air freight & logistics","Airways","Auto Components","Automobiles","Banks","Beverages","Biotechnology","BPOs","Building Products","Capital Markets","Cement","Chemicals","Commercial services & Supplies","Communications Equipment","Construction & Engineering","Construction materials","Consumer Durables","Consumer Finance","Containers & Packaging","Dairy Industry","Defence","Derivatives","Distributors","Diversified Consumer Services","Diversified Financial Services","Diversified Telecommunication Services","E-Commerce","Education & Training","Electric Utilities","Electrical Equipment","Electronic Equipment,Instruments & Components","Energy Equipment & Services","Engineering & Capital Goods","Entertainment","Equity Real Estate Investment Trusts (REITs)","Ferrous Metals","Fertilisers","Financial Services","FMCG","Food & Staples Retailing","Food Products","Gas Utilities","Gems & Jewellery","Hardware","Health Care Equipment & Supplies","Health Care Providers & Services","Health Care Technology","Hotels,Restaurants & Leisure","Household Durables","Household Products","Independent Power and Renewable Electricity Producers","Industrial Parks","Industrial Products","Insurance","Interactive Media & Services","Internet & Direct Marketing Retail","IT/ ITes","Leisure Products","Life Sciences Tools & Services","Logistics","Machinery","Manufacturing","Marine","Media & Entertainment","Metallurgy","Metals & Mining","Mortgage Real Estate Investment Trusts (REITs)","Multiline Retail","Multi-Utilities","Nanotechnology","NBFCs","Non - Ferrous Metals","Oil,Gas & Consumable Fuels","Packaging & Labelling","Paper & Forest Products","Personal Products","Pesticides","Petroleum Products","Pharmaceuticals","Poultry Industry","Power","Production of Bio-Fuels","Professional Services","Railways","Real Estate","Real Estate Management & Development","Renewable energy","Research & Development","Retail","Road Transport","Robotics","Science & Technology","Seed R&D","Semiconductors & Semiconductor Equipment","Shipping & Ports","Software","Specialty Retail","Technology Hardware,Storage & Peripherals","Telecom - Equipment and Accessories","Telecom - Services","Textiles,Apparel & Luxury Goods","Thrifts & Mortgage Finance","Tobacco","Tourism & Hospitality","Trading Companies & Distributors","Transportation infrastructure","Urban Infrastructure","Water Transport","Water Utilities","Wireless Telecommunication Services","Others"].freeze
  CATEGORIES = JSON.parse(ENV.fetch("PORTFOLIO_CATEGORIES", nil))

  SEBI_REPORTING_FIELDS = {
    type_of_investee_company: "Select",
    type_of_security: "Select",
    details_of_security: "TextField",
    isin: "TextField",
    sebi_registration_number: "TextField",
    is_associate: "Select",
    is_managed_or_sponsored_by_aif: "Select",
    sector: "Select",
    offshore_investment: "Select"
  }.freeze

  SELECT_FIELDS_OPTIONS = {
    type_of_investee_company: TYPES_OF_INVESTEE_COMPANY,
    type_of_security: TYPES_OF_SECURITY,
    offshore_investment: %w[Yes No],
    is_associate: %w[Yes No],
    is_managed_or_sponsored_by_aif: %w[Yes No],
    sector: SECTORS
  }.freeze
  # rubocop:enable Layout/SpaceAfterComma

  belongs_to :entity
  belongs_to :portfolio_company, class_name: "Investor"
  has_many :portfolio_cashflows, dependent: :destroy
  has_many :portfolio_investments, dependent: :destroy
  has_many :aggregate_portfolio_investment, dependent: :destroy
  has_many :valuations, dependent: :destroy

  validates :name, :currency, presence: true
  validates :name, uniqueness: { scope: %i[portfolio_company_id currency] }
  validates :category, length: { maximum: 15 }
  validates :sub_category, :sector, length: { maximum: 100 }
  validate :prevent_currency_change, on: :update

  before_save :update_offshore_investment

  def update_offshore_investment
    return if investment_domicile.blank? || !json_fields.key?("offshore_investment")

    json_fields["offshore_investment"] = if investment_domicile.casecmp?("domestic")
                                           "No"
                                         else
                                           "Yes"
                                         end
  end

  def prevent_currency_change
    if will_save_change_to_currency?
      errors.add(:currency, "cannot be updated")
    end
  end

  def to_s
    name
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[category currency created_at investment_domicile name sector startup sub_category updated_at]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[aggregate_portfolio_investment portfolio_company portfolio_investments]
  end
end
