module UserEnabled
  extend ActiveSupport::Concern

  included do
    # Add new flags to the end of this list
    # validates :permissions, presence: true
    flag :permissions, %i[enable_documents enable_deals enable_investments enable_unused
                          enable_secondary_sale enable_funds enable_inv_opportunities enable_options
                          enable_captable enable_investors enable_kpis enable_kycs enable_approvals enable_reports enable_kanban enable_import_uploads enable_investor_advisors enable_form_types enable_user_llm_chat enable_compliance]

    # Add new flags to the end of this list
    flag :extended_permissions, %i[investor_kyc_create investor_kyc_read investor_kyc_update investor_kyc_delete investor_kyc_approve investor_create investor_read investor_update investor_destroy]
  end

  def enable_compliance
    get_permissions.enable_compliance? && entity&.permissions&.enable_compliance?
  end

  def enable_user_llm_chat
    get_permissions.enable_user_llm_chat? && entity&.permissions&.enable_user_llm_chat?
  end

  def enable_documents
    get_permissions.enable_documents? && entity&.permissions&.enable_documents?
  end

  def enable_approvals
    get_permissions.enable_approvals? && entity&.permissions&.enable_approvals?
  end

  def enable_deals
    get_permissions.enable_deals? && entity&.permissions&.enable_deals?
  end

  def enable_kanban
    get_permissions.enable_kanban? && entity&.permissions&.enable_kanban?
  end

  def enable_investments
    get_permissions.enable_investments? && entity&.permissions&.enable_investments?
  end

  def enable_unused
    get_permissions.enable_unused? && entity&.permissions&.enable_unused?
  end

  def enable_secondary_sale
    get_permissions.enable_secondary_sale? && entity&.permissions&.enable_secondary_sale?
  end

  def enable_funds
    get_permissions.enable_funds? && entity&.permissions&.enable_funds?
  end

  def enable_inv_opportunities
    get_permissions.enable_inv_opportunities? && entity&.permissions&.enable_inv_opportunities?
  end

  def enable_options
    get_permissions.enable_options? && entity&.permissions&.enable_options?
  end

  def enable_captable
    get_permissions.enable_captable? && entity&.permissions&.enable_captable?
  end

  def enable_investors
    get_permissions.enable_investors? && entity&.permissions&.enable_investors?
  end

  def enable_kpis
    get_permissions.enable_kpis? && entity&.permissions&.enable_kpis?
  end

  def enable_kycs
    get_permissions.enable_kycs? && entity&.permissions&.enable_kycs?
  end

  def enable_reports
    get_permissions.enable_reports? && entity&.permissions&.enable_reports?
  end

  def get_permissions
    investor_advisor? ? investor_advisor.permissions : permissions
  end

  def get_extended_permissions
    investor_advisor? ? investor_advisor.extended_permissions : extended_permissions
  end

  def enable_import_uploads
    get_permissions.enable_import_uploads?
  end

  def enable_investor_advisors
    get_permissions.enable_investor_advisors?
  end

  def enable_form_types
    get_permissions.enable_form_types?
  end
end
