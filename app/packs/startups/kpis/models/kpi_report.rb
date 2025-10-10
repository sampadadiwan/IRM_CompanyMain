class KpiReport < ApplicationRecord
  include WithCustomField
  include ForInvestor
  include WithFolder
  include Trackable.new

  attr_accessor :delete_kpis, :upload_new_kpis, :update_existing_kpis

  PERIODS = ["Month", "Quarter", "Half Year", "Year", "YTD"].freeze

  STANDARD_COLUMNS = {
    "As Of" => "as_of",
    "Period" => "period",
    "Notes" => "notes",
    "User" => "user_name",
    "For" => "entity_name"
  }.freeze

  TAG_LIST = {
    "Actual" => "Actual",
    "Budget" => "Budget",
    "IC" => "IC"
  }.freeze

  belongs_to :entity
  # This is in case the fund is uploading the kpis
  belongs_to :portfolio_company, class_name: "Investor", optional: true
  belongs_to :owner, class_name: "Entity", optional: true
  belongs_to :user
  has_many :kpis, dependent: :destroy
  has_many :access_rights, as: :owner, dependent: :destroy
  has_many :import_uploads, as: :owner, dependent: :destroy

  validates :period, length: { maximum: 12 }
  validates :as_of, presence: true
  # validates unique kpi report for the entity, period and portfolio_company combination
  validates_uniqueness_of :as_of, scope: %i[entity_id portfolio_company_id period tag_list as_of], message: "A KPI Report for this period already exists for this entity", if: -> { entity_id.present? && period.present? }

  accepts_nested_attributes_for :kpis, reject_if: :all_blank, allow_destroy: true

  scope :for_user, ->(user) { where(entity_id: user.entity_id) }
  scope :for_both, ->(user) { KpiReport.from("(#{for_investor(user).to_sql} UNION #{for_user(user).to_sql}) as kpi_reports") }

  def self.custom_fields
    JSON.parse(ENV.fetch("KPIS", nil)).keys.map(&:titleize).sort
  end

  after_commit :import_kpis
  def import_kpis
    if %w[1 true].include?(delete_kpis)
      self.delete_kpis = false
      # Delete all existing kpis for this report
      kpis.delete_all
      Rails.logger.info "Deleted existing KPIs for KpiReport #{id}"
    end

    self.update_existing_kpis = true if %w[1 true].include?(update_existing_kpis)

    if %w[1 true].include?(upload_new_kpis)
      self.upload_new_kpis = false
      kpi_file = documents.where(name: "KPIs").first
      ImportKpiWorkbookJob.perform_later(id, user_id, update_existing_kpis: update_existing_kpis) if kpi_file.present?

      # Delete any prev csv files
      documents.where(name: "KPIs.csv").delete_all
      # Convert the kpis to csv
      convert_kpis_to_csv
    else
      # If no new kpis are uploaded, we will not import any kpis
      Rails.logger.info "skipping ImportKpiWorkbookJob for KpiReport #{id}"
    end
  end

  def convert_kpis_to_csv
    kpi_file = documents.where(name: "KPIs").first
    if kpi_file.present?
      ConvertKpiToCsvJob.perform_later(id, user_id, kpi_file.id)
    else
      Rails.logger.warn "No KPIs document found for KpiReport #{id}"
    end
  end

  def custom_kpis
    if form_type
      my_kpis = kpis.to_a
      form_type.form_custom_fields.each do |custom_field|
        kpis << Kpi.new(name: custom_field.name, entity_id:) unless custom_field.field_type == "File" || my_kpis.any? { |kpi| kpi.custom_form_field.id == custom_field.id }
      end
    end
    kpis
  end

  def name
    if portfolio_company_id.present?
      "#{portfolio_company.investor_name} - #{as_of}"
    else
      "#{entity.name} - #{as_of}"
    end
  end

  def for_name
    if portfolio_company_id.present?
      portfolio_company.investor_name
    else
      entity.name
    end
  end

  def to_s
    name
  end

  def document_list
    entity.entity_setting.kpi_doc_list
  end

  def folder_path
    if portfolio_company.present?
      "#{portfolio_company.folder_path}/KPIs/#{name.delete('/')}"
    else
      "/KPIs/#{name.delete('/')}"
    end
  end

  def access_rights_changed(access_right)
    # For the specific case of KpiReport, we need to ensure that when the startup give access right to the report, then the startup is registered as a portfolio_company in the fund investor
    if access_right.deleted_at.blank?
      access_right.investors.each do |investor|
        # Setup the portfolio company in the investor if required
        portfolio_company = investor.investor_entity.investors.find_or_initialize_by(investor_entity_id: entity_id, category: "Portfolio Company", primary_email: entity.primary_email)
        portfolio_company.save if portfolio_company.new_record?
        # Update the investor kpi mappings for the portfolio_company
        InvestorKpiMapping.create_from(portfolio_company.entity, self)
      end
    end
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[as_of period tag_list owner_id]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[kpis entity portfolio_company]
  end

  def self.grid(kpi_reports)
    Kpi.where(kpi_report_id: kpi_reports.pluck(:id)).group_by(&:name)
  end

  def investor_for(for_entity_id)
    if portfolio_company_id.present?
      portfolio_company
    else
      Investor.find_by(entity_id: for_entity_id, investor_entity_id: entity_id)
    end
  end

  # Used by the KpiExtractorService to create a new KpiReport

  QUARTER_TO_MONTH = {
    "Q1" => 1,   # January
    "Q2" => 4,   # April
    "Q3" => 7,   # July
    "Q4" => 10   # October
  }.freeze

  DATES_MAP = [
    { input: "Q1 2024", output: "01-01-2024" },
    { input: "Q3 2024", output: "01-07-2024" },
    { input: "Jan 24", output: "01-01-2024" },
    { input: "January 24", output: "01-01-2024" },
    { input: "May 22", output: "01-05-2022" },
    { input: "CY-2024", output: "01-01-2024" },
    { input: "CY-2025", output: "01-01-2025" }
  ].freeze

  def label
    if tag_list.present?
      "#{period}-#{as_of.strftime('%m-%y')}-#{tag_list}"
    else
      "#{period}-#{as_of.strftime('%m-%y')}"
    end
  end

  after_commit :compute_common_size_kpi, on: %i[create update]

  # rubocop:disable Rails/SkipsModelValidations
  def compute_common_size_kpi
    # This method computes the common size KPI for the report
    ikm = portfolio_company&.investor_kpi_mappings&.where(base_for_common_size: true)&.last
    common_size_kpi = kpis.where(investor_kpi_mapping_id: ikm&.id).first

    if common_size_kpi&.value.blank?
      Rails.logger.warn "No common size KPI found or its value is missing for KpiReport #{id} with base_for_common_size set to true"
      return
    end

    kpis.update_all("common_size_value = value / #{common_size_kpi.value.abs} * 100")
  end
  # rubocop:enable Rails/SkipsModelValidations
end
