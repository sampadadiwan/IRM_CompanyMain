class ShareholderPositionPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      if user.entity_type == "Group Company"
        scope.where(entity_id: user.entity.child_ids)
      else
        scope.where(entity_id: user.entity_id)
      end
    end
  end

  # Mirrors InvestmentPolicy: viewing the list of uploaded shareholder positions is gated on the
  # same "Cap Table" feature flag that governs the Shareholding upload/horizontal cap table UI.
  def index?
    user.enable_captable
  end

  def show?
    user.enable_captable
  end

  # Mirrors KpiPolicy: approving/rejecting a staged Fully Diluted Quantity/% update is restricted
  # to company admins and the approver role, and only ever applies to a row still pending review.
  # This is the general/batch permission - used by "Accept All"/"Reject All" (ShareholderPositionsController#approve_all)
  # and as the base check for individually_approvable?/individually_rejectable? below.
  def approve?
    (user.company_admin? || user.has_cached_role?(:approver)) &&
      record.unapproved? &&
      belongs_to_entity?(user, record)
  end

  def reject?
    approve?
  end

  # A pure Fully Dilluted %-only update (see ShareholderPosition#percentage_only_pending_update?)
  # can only be approved/rejected as part of a full batch via "Accept All"/"Reject All" - approving
  # (or rejecting) just one out of several %-only pending updates for the same Portfolio Company +
  # Round would leave that round's % total inconsistent until every other %-only change uploaded
  # alongside it is also resolved. Used by the one-off Accept/Deny buttons/actions
  # (ShareholderPositionsController#approve/#reject) - never by approve_all, which still allows
  # %-only rows through the general approve?/reject? check above.
  def individually_approvable?
    approve? && !record.percentage_only_pending_update?
  end

  def individually_rejectable?
    individually_approvable?
  end
end
