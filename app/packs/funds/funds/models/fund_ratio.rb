# See docs/features/fund_ratio_run.md for the computation_context design and
# how fund_id relates to cross-fund / cross-portfolio runs.
class FundRatio < ApplicationRecord
  include WithValidationRules

  # include Trackable.new
  include ForInvestor

  has_many :documents, as: :owner, dependent: :destroy

  belongs_to :entity
  # fund_id is nil for cross-fund and cross-portfolio rows — those are linked via
  # computation_context instead. Single-fund rows (FundRatiosJob) always have fund_id set.
  belongs_to :fund, optional: true
  # Polymorphic parent: either a FundRatioRun (cross-fund / cross-portfolio) or a
  # PortfolioScenario (scenario-analysis ratios). Nil for single-fund rows.
  belongs_to :computation_context, polymorphic: true, optional: true
  belongs_to :capital_commitment, optional: true
  belongs_to :valuation, optional: true
  belongs_to :owner, polymorphic: true, optional: true

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

  # Cross-fund rows (fund_id: nil) have no parent fund to join against, so the INNER
  # JOIN in ForInvestor#for_company_admin would silently drop them. LEFT JOIN lets them
  # through; the WHERE then scopes them by the fund_ratio's own entity_id. Fund-linked
  # rows still require a live (non-deleted, non-snapshot) fund via the JOIN condition.
  # for_employee intentionally keeps the INNER JOIN, hiding nil-fund rows from employees.
  scope :for_company_admin, lambda { |user|
    entity_ids = user.entity_type == "Group Company" ? user.entity.child_ids : [user.entity_id]
    left_joins(:fund)
      .where(
        "(fund_ratios.fund_id IS NULL AND fund_ratios.entity_id IN (?)) OR funds.entity_id IN (?)",
        entity_ids, entity_ids
      )
  }

  # Marks the latest=true flag per scenario independently, so that e.g. a Default job
  # run never clears the latest flag on Bull Case rows (or any other scenario).
  def self.update_latest(fund, end_date)
    where(fund:).distinct.pluck(:scenario).each do |scenario|
      scoped = where(fund:, scenario:)

      # Skip if a newer ratio already exists for this scenario — the incoming end_date
      # is not the latest, so we must not demote whichever row currently holds that flag.
      last = scoped.order(end_date: :desc).first
      next unless last && last.end_date <= end_date

      scoped.update_all(latest: false)
      scoped.where(end_date:).update_all(latest: true)
    end
  end

  before_create :set_scenario_if_missing
  def set_scenario_if_missing
    # Derive scenario label from the parent computation context's name so FundRatio rows
    # are self-contained for filtering without joining to the parent table.
    # Check against the column default ("Default") because that value is assigned by the
    # database before the callback runs, making scenario.blank? always false on new records.
    col_default = self.class.column_defaults["scenario"]
    if computation_context.present? && (scenario.blank? || scenario == col_default)
      self.scenario = computation_context.name
    end
  end

  def to_s
    "#{name} #{value}"
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[name value owner_type owner_id end_date latest fund_id scenario computation_context_type computation_context_id].sort
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[fund computation_context]
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

    # Cross-run rows have fund_id nil, so fall back to the computation context's fund.
    # Both FundRatioRun (#fund → anchor_fund) and PortfolioScenario (#fund) respond to
    # .fund, so duck typing works without branching. Silently skip if no fund is found.
    effective_fund = fund || computation_context&.fund
    return if effective_fund.nil?

    folder = effective_fund.get_or_create_folder("FundRatios")

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
