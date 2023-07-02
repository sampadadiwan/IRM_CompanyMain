module UserEnabled
  extend ActiveSupport::Concern

  included do
    flag :permissions, %i[enable_documents enable_deals enable_investments enable_holdings
                          enable_secondary_sale enable_funds enable_inv_opportunities enable_options
                          enable_captable enable_investors enable_kpis enable_kycs enable_approvals]

    flag :extended_permissions, %i[investor_kyc_create investor_kyc_read investor_kyc_update investor_kyc_delete investor_kyc_approve investor_create investor_read investor_update investor_destroy]
  end

  def enable_documents
    get_permissions.enable_documents? && entity && entity.enable_documents
  end

  def enable_approvals
    get_permissions.enable_approvals? && entity && entity.enable_approvals
  end

  def enable_deals
    get_permissions.enable_deals? && entity && entity.enable_deals
  end

  def enable_investments
    get_permissions.enable_investments? && entity && entity.enable_investments
  end

  def enable_holdings
    get_permissions.enable_holdings? && entity && entity.enable_holdings
  end

  def enable_secondary_sale
    get_permissions.enable_secondary_sale? && entity && entity.enable_secondary_sale
  end

  def enable_funds
    get_permissions.enable_funds? && entity && entity.enable_funds
  end

  def enable_inv_opportunities
    get_permissions.enable_inv_opportunities? && entity && entity.enable_inv_opportunities
  end

  def enable_options
    get_permissions.enable_options? && entity && entity.enable_options
  end

  def enable_captable
    get_permissions.enable_captable? && entity && entity.enable_captable
  end

  def enable_investors
    get_permissions.enable_investors? && entity && entity.enable_investors
  end

  def enable_kpis
    get_permissions.enable_kpis? && entity && entity.enable_kpis
  end

  def enable_kycs
    get_permissions.enable_kycs? && entity && entity.enable_kycs
  end

  def get_permissions
    investor_advisor? ? investor_advisor.permissions : permissions
  end
end
