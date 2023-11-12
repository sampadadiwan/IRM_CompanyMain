# Steps to migrate
# Deploy and run migration AddPermissionsToEntity
# Once the above step is completed
# Include this module in Entity
# Add the migration DropEnableFieldsForEntity under migration folder
# Deploy and run migration DropEnableFieldsForEntity

module EntityEnabled
  extend ActiveSupport::Concern

  included do
    # Add new flags to the end of this list
    flag :permissions, %i[enable_documents enable_deals enable_investments enable_holdings enable_secondary_sale enable_funds enable_inv_opportunities enable_options enable_captable enable_investors enable_account_entries enable_units enable_fund_portfolios enable_kpis enable_kycs enable_support enable_approvals enable_reports enable_capital_introductions]
  end

  def set_flag_val(flag, val)
    if val
      permissions.set(flag.to_sym)
    else
      permissions.unset(flag.to_sym)
    end
  end

  def enable_documents
    permissions.enable_documents?
  end

  def enable_documents=(val)
    set_flag_val(:enable_documents, val)
  end

  def enable_deals
    permissions.enable_deals?
  end

  def enable_deals=(val)
    set_flag_val(:enable_deals, val)
  end

  def enable_investments
    permissions.enable_investments?
  end

  def enable_investments=(val)
    set_flag_val(:enable_investments, val)
  end

  def enable_holdings
    permissions.enable_holdings?
  end

  def enable_holdings=(val)
    set_flag_val(:enable_holdings, val)
  end

  def enable_secondary_sale
    permissions.enable_secondary_sale?
  end

  def enable_secondary_sale=(val)
    set_flag_val(:enable_secondary_sale, val)
  end

  def enable_funds
    permissions.enable_funds?
  end

  def enable_funds=(val)
    set_flag_val(:enable_funds, val)
  end

  def enable_inv_opportunities
    permissions.enable_inv_opportunities?
  end

  def enable_inv_opportunities=(val)
    set_flag_val(:enable_inv_opportunities, val)
  end

  def enable_options
    permissions.enable_options?
  end

  def enable_options=(val)
    set_flag_val(:enable_options, val)
  end

  def enable_captable
    permissions.enable_captable?
  end

  def enable_captable=(val)
    set_flag_val(:enable_captable, val)
  end

  def enable_investors
    permissions.enable_investors?
  end

  def enable_investors=(val)
    set_flag_val(:enable_investors, val)
  end

  def enable_account_entries
    permissions.enable_account_entries?
  end

  def enable_account_entries=(val)
    set_flag_val(:enable_account_entries, val)
  end

  def enable_fund_portfolios
    permissions.enable_fund_portfolios?
  end

  def enable_fund_portfolios=(val)
    set_flag_val(:enable_fund_portfolios, val)
  end

  def enable_units
    permissions.enable_units?
  end

  def enable_units=(val)
    set_flag_val(:enable_units, val)
  end

  def enable_kpis
    permissions.enable_kpis?
  end

  def enable_kpis=(val)
    set_flag_val(:enable_kpis, val)
  end

  def enable_kycs
    permissions.enable_kycs?
  end

  def enable_kycs=(val)
    set_flag_val(:enable_kycs, val)
  end

  def enable_approvals
    permissions.enable_approvals?
  end

  def enable_approvals=(val)
    set_flag_val(:enable_approvals, val)
  end

  def enable_support
    permissions.enable_support?
  end

  def enable_support=(val)
    set_flag_val(:enable_support, val)
  end

  # def method_missing(method_name, *args, &)
  #   # This is to enable templates to get specific account entries
  #   if method_name.to_s.starts_with?("enable_")
  #     Rails.logger.debug { "method_name: #{method_name}" }
  #     if method_name.to_s.ends_with?("=")
  #       if args[0]
  #         permissions.set(args[0].to_sym)
  #       else
  #         permissions.unset(args[0].to_sym)
  #       end
  #     else
  #       permissions.send("#{method_name}?")
  #     end
  #   end
  # end

  # def respond_to_missing? *_args
  #   true
  # end
end
