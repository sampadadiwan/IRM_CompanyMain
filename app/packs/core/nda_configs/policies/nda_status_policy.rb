# frozen_string_literal: true

# Authorization policy for the GP NDA Status Dashboard.
# All actions are restricted to GP employees of the same entity
# that owns the NDA config. LP users and other-entity GPs are denied.
#
# @see NdaStatusController
# @see NdaConfigPolicy
class NdaStatusPolicy < ApplicationPolicy
  # @return [Boolean] GP can view the status summary in the NDA modal
  def summary?
    gp_same_entity?
  end

  # @return [Boolean] GP can view the dedicated dashboard and export
  def index?
    gp_same_entity?
  end

  # @return [Boolean] GP can mark a user as exempt from the NDA
  def create_exemption?
    gp_same_entity?
  end

  # @return [Boolean] GP can revoke a user's exemption
  def destroy_exemption?
    gp_same_entity?
  end

  private

  # @return [Boolean] Whether the user is a GP employee of the same entity as the NDA config.
  def gp_same_entity?
    user.curr_role_employee? && record.entity_id == user.entity_id
  end
end
