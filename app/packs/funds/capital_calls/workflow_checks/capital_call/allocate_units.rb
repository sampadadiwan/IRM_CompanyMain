# 11. Allocate units — every verified remittance has fund units.
# Worked examples H7, E4 — openspec/changes/archive/2026-10-02-capital-call-journey/design.md#worked-examples
module WorkflowChecks
  module CapitalCall
    class AllocateUnits < WorkflowChecks::Base
      include Support

      self.key = "capital_call.allocate_units"
      self.label = "Allocate units"
      self.workflowable_type = "CapitalCall"

      def call(call)
        verified = remittances(call).where(verified: true)
        units = ::FundUnit.where(owner_type: "CapitalRemittance", owner_id: verified.select(:id))
        without = verified.where.not(id: units.select(:owner_id)).count
        return pass(message: "Units allocated", passed_since: units.maximum(:created_at)) if verified.exists? && without.zero?

        fail_with(message: "#{without} verified #{'remittance'.pluralize(without)} have no units yet",
                  action_label: "Allocate Units", action_path: call_path(call), action_target: ALLOCATE_UNITS_BTN)
      end
    end
  end
end
