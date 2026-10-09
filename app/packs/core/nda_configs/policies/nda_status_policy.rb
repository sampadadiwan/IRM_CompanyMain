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

  # Changed: Removed exemption policy methods — exemption is now on InvestorAccess.
  # Why: Per product decision (2026-10-05) — stakeholder-level exemption.

  # @return [Boolean] GP can tag a user as a designated NDA signatory
  def create_signatory?
    gp_same_entity?
  end

  # @return [Boolean] GP can remove a user's signatory designation
  def destroy_signatory?
    gp_same_entity?
  end

  # Changed: Module 8 — added revoke policy method.
  # Why: GP can revoke an accepted investor's NDA from the dashboard.
  #   Same entity-scoping as other dashboard actions.
  #
  # @return [Boolean] GP can revoke an investor's accepted NDA
  def revoke?
    gp_same_entity?
  end

  # Changed: Module 8 — added send_reminders policy method.
  # Why: GP can send bulk NDA reminders to pending investors' signatories.
  #   Same entity-scoping as other dashboard actions.
  #
  # @return [Boolean] GP can send NDA reminders to pending investors
  def send_reminders?
    gp_same_entity?
  end

  private

  # @return [Boolean] Whether the user is a GP employee of the same entity as the NDA config.
  def gp_same_entity?
    user.curr_role_employee? && record.entity_id == user.entity_id
  end
end
