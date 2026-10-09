# frozen_string_literal: true

# @description Authorization policy for NdaAcceptance. Denies GP employees (same entity
#   as the NDA config's owner) and allows LPs/advisors who have an approved investor
#   relationship with the NDA config's entity.
#
# @note GP employees are short-circuited at the gate (before_action in DocumentsController)
#   and should never reach the acceptance controller. This policy is a safety net.
#
# @see NdaAcceptance
# @see NdaConfigPolicy
class NdaAcceptancePolicy < ApplicationPolicy
  # @return [Boolean] Whether the user can view the NDA acceptance screen.
  def show?
    lp_with_access?
  end

  # @return [Boolean] Whether the user can accept the NDA.
  def create?
    lp_with_access?
  end

  # @return [Boolean] Whether the user can decline the NDA.
  def decline?
    lp_with_access?
  end

  private

  # @return [Boolean] true if the user is NOT from the same entity (not GP) and HAS
  #   an approved investor access to the NDA config's entity.
  def lp_with_access?
    return false if user.entity_id == record.nda_config.entity_id

    InvestorAccess.approved_for(user, record.nda_config.entity).exists?
  end
end
