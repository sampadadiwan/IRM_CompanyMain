class KpiReport < ApplicationRecord
  include WithCustomField
  include ForInvestor
  include WithFolder
  include Trackable.new

  attr_accessor :delete_kpis, :upload_new_kpis, :update_existing_kpis

  PERIODS = ["Month", "Quarter", "Half Year", "Year", "YTD"].freeze

  # File types the KPI workbook upload accepts (Uppy restriction; the server re-checks via Roo).
  WORKBOOK_FILE_TYPES = %w[.xlsx .xls .csv].freeze

  # Outcome of the import that follows a portco submission (import_status column):
  #   pending  → submitted, ImportKpiWorkbookJob not finished yet
  #   imported → data staged (unapproved); the fund has been notified
  #   failed   → the import hit blocking errors; the report was reopened (draft_saved) for the portco
  IMPORT_STATUSES = %w[pending imported failed].freeze

  # Lifecycle of a portco self-reporting request.
  # shell_created → link_sent → draft_saved → submitted → reviewed
  enum :status, {
    shell_created: 'shell_created',
    link_sent: 'link_sent',
    draft_saved: 'draft_saved',
    submitted: 'submitted',
    reviewed: 'reviewed'
  }, prefix: :status

  STANDARD_COLUMNS = {
    "As Of; date-col" => "as_of; date-col",
    "Period; text-col" => "period; text-col",
    "Notes; text-col" => "notes; text-col",
    "User; text-col" => "user_name; text-col",
    "For; text-col" => "entity_name; text-col"
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
  scope :actuals, -> { where(tag_list: "Actual") }
  scope :budgets, -> { where(tag_list: "Budget") }
  scope :ics, -> { where(tag_list: "IC") }
  # Reports that portcos have not yet submitted — used to filter bulk reminders.
  scope :not_submitted, -> { where.not(status: %w[submitted reviewed]) }
  scope :portco_pending, -> { where(enable_portco_upload: true).not_submitted }

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

  # Tells the fund a portco submission has been staged. Called by ImportKpiWorkbookJob after a clean
  # import (never from the request that flipped the status — see kpi_reports_controller#update), so
  # "submitted" in the fund's inbox always means "and the data is there". Sends only to employees
  # tagged "Kpi" if any exist; falls back to all employees. Idempotent via fund_notified_at.
  def notify_fund_of_submission!
    return if fund_notified_at.present?

    recipients = entity.employees.with_tag('Kpi')
    recipients = entity.employees if recipients.empty?
    recipients.find_each do |employee|
      KpiReportSubmittedNotifier.with(record: self, entity_id: entity_id).deliver_later(employee)
    end
    update_columns(fund_notified_at: Time.current)
  end

  # Tells the fund a portco submission could not be imported (post-gate failure — rare) and reopens the
  # report so the portco can fix and resubmit; reminders resume because the status leaves `submitted`.
  def reopen_after_failed_import!
    update_columns(status: 'draft_saved', import_status: 'failed', submitted_at: nil)
    recipients = entity.employees.with_tag('Kpi')
    recipients = entity.employees if recipients.empty?
    recipients.find_each do |employee|
      KpiReportImportFailedNotifier.with(record: self, entity_id: entity_id).deliver_later(employee)
    end
  end

  # Fund-side "reopen and ask for re-upload": back to draft_saved, clear submission markers, re-send the link.
  def reopen_for_portco!(entity_id_for_notification)
    update_columns(status: 'draft_saved', submitted_at: nil, import_status: nil, fund_notified_at: nil)
    SendPortcoNotification.call(model: self, entity_id: entity_id_for_notification)
  end

  # Portco has no non-computed KPI mappings — nothing can be imported from any workbook (§2.7).
  def no_kpi_mappings?
    portfolio_company.present? && portfolio_company.investor_kpi_mappings.not_compute.none?
  end

  def convert_kpis_to_csv
    kpi_file = documents.where(name: "KPIs").first
    if kpi_file.present?
      ConvertKpiToCsvJob.perform_later(id, user_id, kpi_file.id)
    else
      Rails.logger.warn "No KPIs document found for KpiReport #{id}"
    end
  end

  # Launches a new workflow instance on the portfolio company (an Investor) each time a
  # KPI workbook finishes importing for it. This is deliberately an *explicit* call rather
  # than a WorkflowAutoAssignmentRule condition: the auto-assignment engine
  # (see Workflowable#apply_workflow_auto_assignment_on_update) only ever assigns/launches a
  # template ONCE per record — it bails out as soon as workflow_assignment is present. That
  # is correct for the one-time "which template applies to this portfolio company" decision
  # (handled separately, at Investor-creation time, by a category-based auto-assignment rule),
  # but wrong for "launch a fresh review every time new KPIs arrive", since KPI reports are
  # periodic. WorkflowInstanceLaunch itself already refuses to start a second instance while
  # one is still active, so this call is safe to make on every import without extra guarding.
  def launch_portfolio_company_workflow(user)
    # portfolio_company_id has no category constraint at the DB/association level — it can
    # point at any Investor (kpi_reports_controller permits it directly). Without this check,
    # a KpiReport misdirected at a regular (non-portfolio-company) Investor would re-launch
    # a workflow against a record whose one-time "Investor Onboarding" may already be complete.
    return if portfolio_company.blank? || portfolio_company.category != "Portfolio Company" || kpis.none?

    result = WorkflowInstanceLaunch.call(workflowable: portfolio_company, launched_by: user)
    return if result.success?

    # Best-effort: a missing template assignment or an already-active review are both
    # expected, non-error outcomes (e.g. entity hasn't set up the workflow yet, or the
    # previous period's review is still in progress) — log and move on, never raise.
    Rails.logger.warn("[KpiReport#launch_portfolio_company_workflow] KpiReport##{id}: #{result[:errors]}")
  rescue StandardError => e
    # WorkflowInstanceLaunch's step-actor notification (an email) can raise for reasons
    # unrelated to the KPI import itself (e.g. a mail delivery error) — the WorkflowInstance
    # row is already committed by that point (see WorkflowInstanceLaunch's own comment on
    # why notification runs after the transaction), so the review still launched even if the
    # notification failed. Every other call site into this engine (Workflowable#apply_workflow_
    # auto_assignment/_on_update) treats notification failures the same way: log, never let it
    # crash the caller. Here the caller is ImportKpiWorkbookJob — a notification hiccup must
    # not fail the whole KPI import.
    Rails.logger.warn("[KpiReport#launch_portfolio_company_workflow] KpiReport##{id}: #{e.message}")
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
    %w[as_of period tag_list owner_id portfolio_company_id status]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[kpis entity portfolio_company]
  end

  def self.grid(kpi_reports)
    Kpi.where(kpi_report_id: kpi_reports.unscope(:order).pluck(:id)).group_by(&:name)
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

  # after_commit :compute_common_size_kpi, on: %i[create update]

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
