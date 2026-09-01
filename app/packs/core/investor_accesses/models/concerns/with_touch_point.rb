# LP CRM: shared "touch point" behaviour for records that log an interaction
# with a specific person at a stakeholder — currently Note and Task.
#
# The touch point is the contact's InvestorAccess record. An access belongs to
# exactly one Investor, so a touch point is always a person at the owner's LP and
# each contact's history stays cleanly scoped to that stakeholder. The record's
# owner is unchanged (the Investor, or the DealInvestor for deal-side notes and
# tasks) — the touch point is a filter dimension only.
#
# An owner opts in by defining two methods:
#   * #touch_point_options       — the [label, investor_access_id] dropdown pairs
#   * #touch_point_investor_id   — the LP whose contacts are allowed here
# Investor answers with its own id; DealInvestor answers with its parent LP's id,
# which is what lets a note logged inside a deal name the same people as a note
# logged on the stakeholder record.
module WithTouchPoint
  extend ActiveSupport::Concern

  included do
    belongs_to :touch_point, class_name: "InvestorAccess", optional: true

    # The UI dropdown only offers the owner's contacts, but params are not to be
    # trusted: without this check a crafted POST could attach any InvestorAccess —
    # including another entity's — and its name/email would render in the lists.
    validate :touch_point_belongs_to_owner, if: -> { touch_point_id.present? }
  end

  # Duck-typed deliberately: any owner able to offer touch points answers
  # #touch_point_investor_id, and every other owner type (User, Fund,
  # SideLetterObligation…) simply cannot carry one.
  def touch_point_belongs_to_owner
    allowed_investor_id = owner.touch_point_investor_id if owner.respond_to?(:touch_point_investor_id)
    return if allowed_investor_id.present? && touch_point&.investor_id == allowed_investor_id

    errors.add(:touch_point_id, "is not a contact of this stakeholder")
  end
end
