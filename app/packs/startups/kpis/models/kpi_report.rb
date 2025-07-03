class KpiReport < ApplicationRecord
  include WithCustomField
  include ForInvestor
  include WithFolder
  include Trackable.new

  attr_accessor :delete_kpis, :upload_new_kpis

  PERIODS = ["Month", "Quarter", "Half Year", "Year", "YTD"].freeze

  STANDARD_COLUMNS = {
    "As Of" => "as_of",
    "Period" => "period",
    "Notes" => "notes",
    "User" => "user_name",
    "For" => "entity_name"
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

    if %w[1 true].include?(upload_new_kpis)
      self.upload_new_kpis = false
      kpi_file = documents.where(name: "KPIs").first
      ImportKpiWorkbookJob.perform_later(id, user_id) if kpi_file.present?
    else
      # If no new kpis are uploaded, we will not import any kpis
      Rails.logger.info "skipping ImportKpiWorkbookJob for KpiReport #{id}"
    end
  end

  after_create_commit :convert_kpis_to_csv
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

  CONVERT_TO_DATE = {}.freeze

  def self.convert_to_date(query)
    date = CONVERT_TO_DATE[query]
    if date.nil?
      # Use few shot prompt template to generate a report url
      prompt = Langchain::Prompt::FewShotPromptTemplate.new(
        # The prefix is the text should contain the model class and the searchable attributes
        prefix: "You are a financial analyst who can convert dates in different formats to a standard date format. Convert the given date to a standard date format, dont provide additional info, just the date in dd-mm-yyyy format.",
        suffix: "Input: {query}\nOutput:",
        example_prompt: Langchain::Prompt::PromptTemplate.new(
          input_variables: %w[input output],
          template: "Input: {input}\nOutput: {output}"
        ),
        examples: DATES_MAP,
        input_variables: ["query"]
      )

      llm_prompt = prompt.format(query:)

      @llm ||= Langchain::LLM::OpenAI.new(api_key: Rails.application.credentials["OPENAI_API_KEY"])
      llm_response = @llm.chat(messages: [{ role: "user", content: llm_prompt }]).completion
      Rails.logger.debug llm_response
      response = llm_response.sub(/^Output:\s*/, '')
      date = Date.parse(response)
      CONVERT_TO_DATE[query] = date
    end
    date
  end

  def self.convert_to_date2(input_string)
    if input_string.match?(/\AQ[1-4] \d{4}\z/)
      # Handle quarter strings like "Q1 2024"
      quarter, year = input_string.split
      year = year.to_i

      # Map the quarter to the start month
      month = QUARTER_TO_MONTH[quarter]

      Date.new(year, month, 1)

    elsif input_string.match?(/\ACY \d{4}\z/)
      # Handle calendar year strings like "CY-2024"
      year = input_string.split('-')[1].to_i
      Date.new(year, 1, 1) # Start of the calendar year (January 1st)

    else
      raise ArgumentError, "Invalid format #{input_string}. Expected format: 'Q1 YYYY' or 'CY-YYYY'"
    end
  end

  def label
    if tag_list.present?
      "#{period}-#{as_of.strftime('%m-%y')}-#{tag_list}"
    else
      "#{period}-#{as_of.strftime('%m-%y')}"
    end
  end
end
