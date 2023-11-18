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
    flag :permissions, %i[enable_documents enable_deals enable_investments enable_holdings enable_secondary_sale enable_funds enable_inv_opportunities enable_options enable_captable enable_investors enable_account_entries enable_units enable_fund_portfolios enable_kpis enable_kycs enable_support enable_approvals enable_reports]
  end

  # This is for legacy code only, user entity.permissions.enable_xyz? going forward
  # Creates enable_xyz methods on Entity, to get or set the underlying permissions bitflag
  def method_missing(method_name, *args, &)
    if method_name.to_s.starts_with?("enable_")
      Rails.logger.debug { "EntityEnabled.method_missing method_name: #{method_name} #{args}" }
      if method_name.to_s.ends_with?("=")
        flag_name = method_name.to_s.delete("=").to_sym
        if args[0] == true || args[0] == "true" || args[0] == 1
          # puts "setting '#{flag_name}'"
          permissions.set(flag_name)
        else
          # puts "unsetting '#{flag_name}'"
          permissions.unset(flag_name)
        end
      else
        permissions.send("#{method_name}?")
      end
    end
  end

  def respond_to_missing? *_args
    true
  end
end
