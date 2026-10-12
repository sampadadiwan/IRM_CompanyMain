# Whether an order with a journey has cleared every pre-deal step of ITS template (the template is
# editable, so steps an admin removed don't count). A step counts as cleared when its skip check
# passes (not applicable) or its check passes.
# Worked examples E19, E21, E22, E25 — openspec/changes/open-ended-funds/design.md#worked-examples
class OrderJourneyStatus
  PRE_DEAL_KEYS = DealingOrderJourneySetup::PRE_DEAL_CHECKS.map { |c| "#{DealingOrderJourneySetup::KEY_PREFIX}#{c}" }.freeze

  def self.ready_to_deal?(order)
    waiting_on(order).nil?
  end

  # Name of the first pre-deal step not yet cleared, or nil
  def self.waiting_on(order)
    steps = order.workflow_template&.workflow_steps&.order(:position)&.select { |s| PRE_DEAL_KEYS.include?(s.check_key) } || []
    pending = steps.find do |step|
      skipped = step.skip_key.present? && WorkflowChecks::Registry.registered?(step.skip_key) && WorkflowChecks::Registry.fetch(step.skip_key).call(order).passed
      !skipped && !WorkflowChecks::Registry.fetch(step.check_key).call(order).passed
    end
    pending&.name
  end
end
