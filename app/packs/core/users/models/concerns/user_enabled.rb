module UserEnabled
  extend ActiveSupport::Concern

  included do
    flag :permissions, %i[enable_documents enable_deals enable_investments enable_holdings
                          enable_secondary_sale enable_funds enable_inv_opportunities enable_options
                          enable_captable enable_investors]
  end

  def enable_documents
    permissions.enable_documents? && entity.enable_documents
  end

  def enable_deals
    permissions.enable_deals? && entity.enable_deals
  end

  def enable_investments
    permissions.enable_investments? && entity.enable_investments
  end

  def enable_holdings
    permissions.enable_holdings? && entity.enable_holdings
  end

  def enable_secondary_sale
    permissions.enable_secondary_sale? && entity.enable_secondary_sale
  end

  def enable_funds
    permissions.enable_funds? && entity.enable_funds
  end

  def enable_inv_opportunities
    permissions.enable_inv_opportunities? && entity.enable_inv_opportunities
  end

  def enable_options
    permissions.enable_options? && entity.enable_options
  end

  def enable_captable
    permissions.enable_captable? && entity.enable_captable
  end

  def enable_investors
    permissions.enable_investors?
  end
end
