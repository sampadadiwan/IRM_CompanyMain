# The test environment is used exclusively to run your application's
# test suite. You never need to work with it otherwise. Remember that
# your test database is "scratch space" for the test suite and is wiped
# and recreated between test runs. Don't rely on the data there!

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # While tests run files are not watched, reloading is not necessary.
  config.enable_reloading = false

  # Eager loading loads your entire application. When running a single test locally,
  # this is usually not necessary, and can slow down your test suite. However, it's
  # recommended that you enable it in continuous integration systems to ensure eager
  # loading is working properly before deploying your code.
  config.eager_load = ENV["CI"].present?

  # Configure public file server for tests with cache-control for performance.
  config.public_file_server.headers = { "cache-control" => "public, max-age=3600" }

  # Show full error reports.
  config.consider_all_requests_local = true
  config.cache_store = :null_store

  # Render exception templates for rescuable exceptions and raise for other exceptions.
  config.action_dispatch.show_exceptions = :rescuable

  # Disable request forgery protection in test environment.
  config.action_controller.allow_forgery_protection = false

  # Store uploaded files on the local file system in a temporary directory.
  config.active_storage.service = :test

  # Tell Action Mailer not to deliver emails to the real world.
  # The :test delivery method accumulates sent emails in the
  # ActionMailer::Base.deliveries array.
  config.action_mailer.delivery_method = :test
  config.action_mailer.perform_deliveries = true

  # Print deprecation notices to the stderr.
  config.active_support.deprecation = :stderr

  # Raises error for missing translations.
  # config.i18n.raise_on_missing_translations = true

  # Annotate rendered view with file names.
  # config.action_view.annotate_rendered_view_with_filenames = true
  config.active_job.queue_adapter = :inline
  # Raise error when a before_action's only/except options reference missing actions.
  config.action_controller.raise_on_missing_callback_actions = false

  config.action_dispatch.show_exceptions = false

  Bullet.enable        = true
  Bullet.bullet_logger = true  # writes N+1 warnings to log/bullet.log
  Bullet.rails_logger  = true  # also echoes into log/test.log for correlation
  Bullet.raise         = false # let the full suite run; we'll analyze after
  Bullet.alert         = false # no browser alerts in headless tests
  Bullet.console       = false # no JS console noise
  Bullet.add_footer    = false # not useful in headless tests

  # Safelist: associations that are eagerly loaded and used in production UI
  # but not exercised in every test scenario (genuine AVOID false positives).
  # Also covers conflicted AVOIDs — associations that appear as AVOID in some
  # paths and USE in others; removing them would create real N+1s.
  # Rule: NEVER remove an includes because of AVOID — only safelist it here.
  [
    ["AccessRight",                  :investor],
    ["AccessRight",                  :user],
    ["AggregatePortfolioInvestment", :investment_instrument],
    ["AggregatePortfolioInvestment", :portfolio_investments],
    ["ApprovalResponse",             :response_entity],
    ["ApprovalResponse",             :response_user],
    ["Audited::Audit",               :auditable],
    ["Audited::Audit",               :user],
    ["CapitalCommitment",            :investor_kyc],
    ["CapitalDistributionPayment",   :capital_commitment],
    ["CapitalDistributionPayment",   :entity],
    ["CapitalDistributionPayment",   :investor_kyc],
    ["CapitalRemittance",            :capital_call],
    ["CapitalRemittance",            :capital_commitment],
    ["CapitalRemittance",            :document_folder],
    ["CapitalRemittance",            :documents],
    ["CapitalRemittance",            :entity],
    ["CapitalRemittance",            :form_type],
    ["CapitalRemittance",            :fund],
    ["CapitalRemittance",            :investor],
    ["CapitalRemittance",            :investor_kyc],
    ["DealActivity",                 :rich_text_details],
    ["Deal",                         :deal_investors],
    ["DealInvestor",                 :deal],
    ["DealInvestor",                 :deal_activities],
    ["DealInvestor",                 :investor],
    ["DealInvestor",                 :rich_text_notes],
    ["Document",                     :e_signatures],
    ["Document",                     :folder],
    ["Document",                     :stamp_papers],
    ["ESignature",                   :entity],
    ["ExpressionOfInterest",         :investor],
    ["Folder",                       :parent],
    ["FormCustomField",              :rich_text_info],
    ["FormType",                     :form_custom_fields],
    ["Fund",                         :account_entries],
    ["Fund",                         :capital_commitments],
    ["Fund",                         :fund_ratios],
    ["FundFormula",                  :entity],
    ["FundFormula",                  :fund],
    ["FundRatio",                    :capital_commitment],
    ["FundRatio",                    :computation_context],
    ["FundRatio",                    :fund],
    ["Interest",                     :interest_entity],
    ["Investment",                   :portfolio_company],
    ["InvestmentInstrument",         :portfolio_company],
    ["Investor",                     :entity],
    ["Investor",                     :investor_accesses],
    ["Investor",                     :investor_entity],
    ["KanbanCard",                   :entity],
    ["KanbanCard",                   :kanban_board],
    ["KanbanColumn",                 :entity],
    ["KanbanColumn",                 :kanban_board],
    ["KanbanColumn",                 :kanban_cards],
    ["Kpi",                          :kpi_report],
    ["Kpi",                          :owner],
    ["KpiReport",                    :documents],
    ["KpiReport",                    :entity],
    ["KpiReport",                    :kpis],
    ["KpiReport",                    :owner],
    ["KpiReport",                    :portfolio_company],
    ["KpiReport",                    :user],
    ["PortfolioInvestment",          :fund],
    ["PortfolioInvestment",          :investment_instrument],
    ["ScenarioInvestment",           :investment_instrument],
    ["ScenarioInvestment",           :user],
    ["Task",                         :for_entity],
    ["Task",                         :rich_text_response],
    ["Task",                         :task_template],
    ["Task",                         :user],
    ["User",                         :roles],
    ["User",                         :roles_users],
    ["Valuation",                    :entity],
    ["Valuation",                    :form_type],
    ["Valuation",                    :owner],
    ["PortfolioScenario",            :scenario_investments],
    ["ScenarioInvestment",           :fund],
    ["ScenarioInvestment",           :portfolio_company],
    ["AggregatePortfolioInvestment", :portfolio_company],
    # Investor#notification_users uses approved_users.includes(:roles) — roles may be unused
    # in code paths that don't call has_cached_role? (e.g., no-model case).
    ["User",                         :roles],
    # Investor approved_users/approved_investor_accesses — included for send_kyc_link/send_reminder
    # but unused in bulk actions that don't call those paths (e.g., verify).
    ["Investor",                     :approved_users],
    ["Investor",                     :approved_investor_accesses],
    # Allocation associations included for bulk actions — not all are accessed in every code path.
    ["Allocation",                   :offer],
    ["Allocation",                   :interest],
    ["Allocation",                   :entity],
    ["Allocation",                   :secondary_sale],
    ["Allocation",                   :form_type],
    ["Allocation",                   :documents],
    # InvestorKyc bulk job includes document_folder and form_type — unused in non-doc paths.
    ["IndividualKyc",                :document_folder],
    ["IndividualKyc",                :form_type],
    ["NonIndividualKyc",             :form_type],
    # Fund#entity is eagerly loaded for the portfolio_investments JSON view.
    # In HTML views the entity is not accessed, so it triggers AVOID there.
    ["Fund",                         :entity],
    # Task destroy_series preloads these for the dependent: :destroy chain.
    # Unused in the single-task destroy path.
    ["Task",                         :documents],
    ["Task",                         :folders],
    ["Task",                         :reminders],
    ["Task",                         :noticed_events],
    # InvestorKyc bulk job includes entity_setting nested in investor_entity.
    # Unused in code paths that don't call enable_kyc.
    ["Entity",                       :entity_setting],
    # PortfolioInvestments: the JSON view uses aggregate_portfolio_investment, portfolio_company,
    # and valuation, but the HTML (ransack_table) view does not. Conflicted include — safelist.
    ["PortfolioInvestment",          :aggregate_portfolio_investment],
    ["PortfolioInvestment",          :portfolio_company],
    ["PortfolioInvestment",          :valuation],
    # NonIndividualKyc: document_folder included for all KYC bulk actions but only accessed
    # when the action involves document folder operations (not all paths use it).
    ["NonIndividualKyc",             :document_folder],
  ].each do |klass, assoc|
    Bullet.add_safelist type: :unused_eager_loading, class_name: klass, association: assoc
  end
  # config.logger = Logger.new(STDOUT)
  config.log_level = :debug
  config.active_record.verbose_query_logs = true

  config.after_initialize do
    Chewy.logger = Rails.logger
  end

  config.assets.unknown_asset_fallback = true if config.respond_to?(:assets)
end
