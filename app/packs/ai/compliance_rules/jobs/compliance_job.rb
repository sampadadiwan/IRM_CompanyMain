class ComplianceJob < ApplicationJob
  queue_as :default

  def perform(fund_id, schedule)
    fund = Fund.find(fund_id)
    # For each entity that has enable_compliance
    Entity.where_permissions(:enable_compliance).each do |entity|
      # Grab the enabled compliance rules for this entity
      rules_to_run = entity.compliance_rules.enabled.for_schedule(schedule).group_by(&:for_class)
      rules_to_run.each_key do |class_name|
        fund.send(class_name.underscore.to_sym).each do |record|
        end
      end
    end
  end
end
