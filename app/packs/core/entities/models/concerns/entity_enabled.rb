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
    flag :permissions, %i[enable_documents enable_deals enable_investments enable_unused enable_secondary_sale enable_funds enable_inv_opportunities enable_options enable_captable enable_investors enable_account_entries enable_units enable_fund_portfolios enable_kpis enable_kycs enable_support enable_approvals enable_reports enable_whatsapp enable_kanban enable_import_uploads enable_investor_advisors enable_form_types enable_user_llm_chat enable_doc_llm_validation enable_compliance enable_sebi_fields enable_ai_chat]

    flag :customization_flags, %i[investor_kyc_custom_cols capital_commitment_custom_cols capital_remittance_custom_cols capital_distribution_payment_custom_cols investor_custom_cols enable_exchange_rate_commitment_adjustment]
  end

  # This is for legacy code only, use entity.permissions.enable_xyz? going forward
  # Creates enable_xyz methods on Entity, to get or set the underlying permissions bitflag
  def method_missing(method_name, *args, &)
    if method_name.to_s.starts_with?("enable_")
      Rails.logger.debug { "EntityEnabled.method_missing method_name: #{method_name} #{args}" }
      if method_name.to_s.ends_with?("=")
        flag_name = method_name.to_s.delete("=").to_sym
        if [true, "true", 1, "1"].include?(args[0])
          # puts "setting '#{flag_name}'"
          permissions.set(flag_name)
        else
          # puts "unsetting '#{flag_name}'"
          permissions.unset(flag_name)
        end
      else
        permissions.send(:"#{method_name}?")
      end
    end
  end

  def respond_to_missing?(method_name, _include_private = false)
    method_name.to_s.starts_with?("enable_")
  end

  # Counts the investors for a given entity_id, which have the input permission enabled
  # E.x investors_enabled(:enable_deals) => 5
  def investors_enabled_count(enable_permission)
    Entity.joins(:investees).where("investors.entity_id=?", id).where_permissions(enable_permission.to_s).count
  end

  # Find the investors whose entity permissions do not have the input enable_permission
  # and set the enable_permission on them
  # E.x investors_enable(:enable_deals) => 5
  def investors_enable(enable_permission)
    entities = Entity.joins(:investees).where("investors.entity_id=?", id).where_not_permissions(enable_permission.to_s)
    before_count = entities.count
    entities.each do |e|
      e.permissions.set(enable_permission.to_sym)
      e.save
    end
    after_count = entities.count
    [before_count, after_count]
  end

  def investors_disable(disable_permission)
    entities = Entity.joins(:investees).where("investors.entity_id=?", id).where_permissions(disable_permission.to_s)
    before_count = entities.count

    entities.each do |e|
      e.permissions.unset(disable_permission.to_sym)
      e.save
    end

    after_count = entities.count
    [before_count, after_count]
  end
end
