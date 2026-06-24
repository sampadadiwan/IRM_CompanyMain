# frozen_string_literal: true

# Authorizes access to customer support escalation records.
# Restricted to support users mapped to the escalation's entity
# via SupportClientMapping.
#
# @see CustomerSupportEscalationsController
# @see CustomerSupportEscalation
class CustomerSupportEscalationPolicy < ApplicationPolicy
  # @return [Boolean] true if user is a support team member
  def show?
    support?
  end

  # @return [Boolean] true if user is a support team member
  def update?
    support?
  end

  class Scope < ApplicationPolicy::Scope
    # Returns escalations scoped to the support user's assigned entities.
    #
    # @return [ActiveRecord::Relation] escalations for the user's mapped entities
    def resolve
      if user.support?
        mapped_entity_ids = SupportClientMapping.where(user: user, enabled: true).pluck(:entity_id)
        scope.where(entity_id: mapped_entity_ids)
      else
        scope.none
      end
    end
  end
end
