# frozen_string_literal: true

# Authorizes access to the CS Feedback Review Dashboard.
# Restricted to support users (Caphive internal team) who can view
# and action feedback items and escalations across all entities.
#
# @see CsFeedbackReviewsController
# @see AgentChatMessageFeedback
class CsFeedbackReviewPolicy < ApplicationPolicy
  # @return [Boolean] true if user is a support team member
  def index?
    support?
  end

  # @return [Boolean] true if user is a support team member
  def show?
    support?
  end

  # @return [Boolean] true if user is a support team member
  def update?
    support?
  end

  # @return [Boolean] true if user is a support team member
  def retest?
    support?
  end

  class Scope < ApplicationPolicy::Scope
    # Returns feedback records scoped to the support user's assigned entities.
    # Support users only see entities they are mapped to via SupportClientMapping.
    #
    # @return [ActiveRecord::Relation] feedback records for the user's mapped entities
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
