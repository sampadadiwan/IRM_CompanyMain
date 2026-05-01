class FundRatio < ApplicationRecord
  # include Trackable.new
  include ForInvestor

  has_many :documents, as: :owner, dependent: :destroy

  belongs_to :entity
  belongs_to :fund
  belongs_to :capital_commitment, optional: true
  belongs_to :valuation, optional: true
  belongs_to :owner, polymorphic: true, optional: true
  belongs_to :portfolio_scenario, optional: true

  STANDARD_COLUMNS = {
    "For; text-col" => "owner_name; text-col",
    "Type; text-col" => "owner_type; text-col",
    "Name; text-col" => "name; text-col",
    "Display Value; num-col" => "display_value; num-col",
    "On; date-col" => "end_date; date-col",
    "Scenario; text-col" => "scenario; text-col"
  }.freeze

  ADDITIONAL_COLUMNS_FROM = ["fund"].freeze

  CONDENSED_COLUMNS = {
    "Name; text-col" => "name; text-col",
    "Display Value; num-col" => "display_value; num-col",
    "On; date-col" => "end_date; date-col"
  }.freeze

  COMMITMENT_CONDENSED_COLUMNS = {
    "For; text-col" => "owner_name; text-col",
    "Name; text-col" => "name; text-col",
    "Display Value; num-col" => "display_value; num-col",
    "On; date-col" => "end_date; date-col"
  }.freeze

  validates :display_value, :label, length: { maximum: 50 }
  validates :name, :owner_type, length: { maximum: 255 }

  scope :latest, -> { where(latest: true) }
  scope :default, -> { where(scenario: "Default") }
  scope :for_portfolio_companies, -> { where(owner_type: "PortfolioCompany") }
  scope :for_fund, ->(fund_id) { where(fund_id:, owner_type: "Fund") }

  before_create :set_scenario_if_missing
  def set_scenario_if_missing
    self.scenario = portfolio_scenario.name if (scenario.blank? || scenario == "Default") && portfolio_scenario.present?
  end

  def to_s
    "#{name} #{value}"
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[name value owner_type owner_id end_date latest fund_id scenario].sort
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[fund portfolio_scenario]
  end

  def create_cashflow_document(cash_flows, user_id)
    return if cash_flows.blank?

    csv_data = if cash_flows.is_a?(Array)
                 # If it's XirrCashflow (Array of XirrTransaction), we need to handle it differently
                 if cash_flows.first.is_a?(XirrTransaction)
                   all_keys = %w[date amount notes]
                   CSV.generate do |csv|
                     csv << all_keys.map(&:titleize)
                     cash_flows.each do |tx|
                       csv << [tx.date, tx.amount, tx.notes]
                     end
                   end
                 else
                   all_keys = cash_flows.flat_map { |cf| cf.respond_to?(:keys) ? cf.keys : [] }.uniq
                   CSV.generate do |csv|
                     csv << all_keys.map(&:to_s).map(&:titleize)
                     cash_flows.each do |cf|
                       csv << all_keys.map { |key| cf[key] }
                     end
                   end
                 end
               elsif cash_flows.is_a?(Hash)
                 CSV.generate do |csv|
                   csv << cash_flows.keys.map(&:to_s).map(&:titleize)
                   csv << cash_flows.values
                 end
               end

    return if csv_data.blank?

    folder = fund.get_or_create_folder("FundRatios")

    temp_file = Tempfile.new(["cash_flows_#{id}", ".csv"])
    temp_file.write(csv_data)
    temp_file.rewind

    begin
      Document.create!(
        name: "Cash Flows - #{name} - #{end_date}.csv",
        file: temp_file,
        user_id: user_id,
        owner: self,
        folder: folder,
        entity_id: entity_id,
        orignal: true
      )
    ensure
      temp_file.close
      temp_file.unlink
    end
  end
end
