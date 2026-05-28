module UserGuideHelper
  USER_GUIDE_MAPPING = {
    # Fundraising & Opportunities
    'investment_opportunities' => 'investment_opportunity_user_guide.md',
    'expression_of_interests' => 'investment_opportunity_user_guide.md',

    'deals' => 'deals_management_user_guide.md',
    'deal_activities' => 'deals_management_user_guide.md',
    'deal_investors' => 'deals_management_user_guide.md',

    # Operations & Workflow
    'approvals' => 'approvals_user_guide.md',
    'tasks' => 'tasks_user_guide.md',
    'task_templates' => 'tasks_user_guide.md',
    'e_signatures' => 'esigning_user_guide.md',
    'report_builder' => 'report_builder_user_guide.md',
    'reports' => 'report_builder_user_guide.md',

    # Investor Management
    'investors' => 'investors_user_guide.md',
    'rm_mappings' => 'investors_user_guide.md',
    'investor_accesses' => 'investor_access_tutorial.md',
    'investor_advisors' => 'investor_advisor_user_guide.md',
    'investor_kycs' => 'investor_kyc_user_guide.md',
    'kyc_datas' => 'investor_kyc_user_guide.md',
    'aml_reports' => 'investor_kyc_user_guide.md',

    # Entity Management
    'entities' => 'entities_user_guide.md',
    'entity_settings' => 'entities_user_guide.md',

    # User & Role Management
    'users' => 'user_role_management_user_guide.md',
    'roles' => 'user_role_management_user_guide.md',

    # Portfolio & Valuations
    'portfolio_investments' => 'portfolio_investments_user_guide.md',
    'aggregate_portfolio_investments' => 'portfolio_investments_user_guide.md',
    'portfolio_cashflows' => 'portfolio_investments_user_guide.md',
    'portfolio_scenarios' => 'portfolio_investments_user_guide.md',
    'stock_conversions' => 'portfolio_investments_user_guide.md',
    'stock_adjustments' => 'portfolio_investments_user_guide.md',
    'investment_instruments' => 'portfolio_investments_user_guide.md',
    'valuations' => 'valuations_user_guide.md',

    # Fund Management
    'capital_calls' => 'capital_calls_user_guide.md',
    'capital_remittances' => 'capital_calls_user_guide.md',
    'capital_remittance_payments' => 'capital_calls_user_guide.md',
    'capital_distributions' => 'capital_distributions_user_guide.md',
    'capital_distribution_payments' => 'capital_distributions_user_guide.md',
    'capital_commitments' => 'capital_commitments_user_guide.md',
    'commitment_adjustments' => 'capital_commitments_user_guide.md',
    'account_entries' => 'capital_commitments_user_guide.md',
    'carry_computations' => 'carry_computations_user_guide.md',
    'fund_ratios' => 'fund_ratios_user_guide.md',
    'fund_ratio_run_templates' => 'fund_ratio_run_templates_user_guide.md',
    'fund_units' => 'fund_units_user_guide.md',
    'fund_unit_settings' => 'fund_units_user_guide.md',
    'ratio_formulas' => 'ratio_formulas_user_guide.md',

    # Secondary Sales
    'secondary_sales' => 'secondary_sales_user_guide.md',
    'offers' => 'secondary_sales_user_guide.md',
    'interests' => 'secondary_sales_user_guide.md',
    'allocations' => 'secondary_sales_user_guide.md',

    # Document Management
    'documents' => 'document_management_user_guide.md',
    'folders' => 'document_management_user_guide.md',
    'doc_shares' => 'document_management_user_guide.md',
    'doc_questions' => 'document_management_user_guide.md',

    # Custom Fields
    'form_custom_fields' => 'custom_fields_user_guide.md',
    'form_types' => 'custom_fields_user_guide.md',

    # Analytics & Dashboards
    'dashboard_widgets' => 'dashboard_widgets_user_guide.md',
    'dashboards' => 'dashboard_widgets_user_guide.md',
    'kpis' => 'kpi_flexible_charts_user_guide.md',
    'kpi_chart_settings' => 'kpi_flexible_charts_user_guide.md',
    'investor_kpi_mappings' => 'kpi_flexible_charts_user_guide.md',
    'kpi_reports' => 'kpi_upload_user_guide.md',

    # AI & Support
    'ai_rules' => 'ai_features_user_guide.md',
    'ai_checks' => 'ai_features_user_guide.md',
    'ai_portfolio_reports' => 'ai_features_user_guide.md',
    'ai_report_sections' => 'ai_features_user_guide.md',
    'investment_criteria_templates' => 'ai_features_user_guide.md',
    'chats' => 'ai_features_user_guide.md',
    'faq_threads' => 'ai_features_user_guide.md',
    'report_insights' => 'ai_features_user_guide.md',
    'support_agents' => 'ai_features_user_guide.md',
    'agent_schedules' => 'ai_features_user_guide.md',
    'support_agent_chats' => 'ai_features_user_guide.md',
    'agent_charts' => 'ai_features_user_guide.md',

    # Validation Rules
    'validation_rule_overrides' => 'validation_rule_engine_user_guide.md',
    'validation_rules' => 'validation_rule_engine_user_guide.md',

    # Settings & Utilities
    'exchange_rates' => 'tracking_currency_guide.md',
    'db_dumps' => 'db_dumps_user_guide.md',
    'outlook_addin' => 'outlook_setup_user_guide.md'
  }.freeze

  def current_user_guide_path
    guide_file = if action_name == 'show_deleted'
                   "data_recovery_user_guide"
                 else
                   USER_GUIDE_MAPPING[controller_name]&.gsub('.md', '')
                 end

    return nil unless guide_file

    # Use the internal route instead of direct file link
    Rails.application.routes.url_helpers.user_guide_path(guide_file)
  end

  def user_guide_info_icon
    return nil if current_user&.curr_role == "investor"

    guide_path = current_user_guide_path
    return nil unless guide_path

    link_to guide_path, target: "_blank", 'data-bs-toggle': 'tooltip', title: 'User Guide',
                        class: 'btn btn-info p-0 rounded-circle d-inline-flex align-items-center justify-content-center',
                        style: 'width: 35px; height: 35px;', rel: 'noopener' do
      content_tag(:i, '', class: 'ti ti-info-circle fs-5', style: 'margin: 0 !important;')
    end
  end

  # Renders a guide icon for an explicit controller key regardless of the current controller.
  # Use when a view needs to link to a guide that differs from (or supplements) its own.
  def user_guide_icon_for(controller_key, tooltip: 'User Guide')
    return nil if current_user&.curr_role == "investor"

    guide_file = USER_GUIDE_MAPPING[controller_key.to_s]&.gsub('.md', '')
    return nil unless guide_file

    guide_path = Rails.application.routes.url_helpers.user_guide_path(guide_file)
    link_to guide_path, target: "_blank", 'data-bs-toggle': 'tooltip', title: tooltip,
                        class: 'btn btn-info p-0 rounded-circle d-inline-flex align-items-center justify-content-center',
                        style: 'width: 35px; height: 35px;', rel: 'noopener' do
      content_tag(:i, '', class: 'ti ti-info-circle fs-5', style: 'margin: 0 !important;')
    end
  end
end
