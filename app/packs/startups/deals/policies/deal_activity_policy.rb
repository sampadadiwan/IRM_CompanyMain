class DealActivityPolicy < DealBasePolicy
  class Scope < Scope
    # L11 — the list matched show?: company admins, support and group companies see every activity of
    # their firm(s); anyone else only the activities of deals in their own deal list (DealPolicy::Scope),
    # as show? asks DealPolicy / DealInvestorPolicy. Tests L11-2, L11-H2 —
    # features/security/security_review_2026_10_low.feature
    def resolve
      if user.entity_type == "Group Company"
        # A group company sees its child firms' activities, as before
        scope.where(entity_id: user.entity.child_ids)
      elsif (user.curr_role == "employee" && user.has_cached_role?(:company_admin)) || user.support?
        # Admins and support: every activity of the firm, as before
        scope.where("deal_activities.entity_id=?", user.entity_id)
      else
        # Everyone else: the firm's activities on deals this user can see
        visible_deals = DealPolicy::Scope.new(user, Deal).resolve.unscope(:order).select(:id)
        scope.where("deal_activities.entity_id=?", user.entity_id).where(deal_id: visible_deals)
      end
    end
  end

  def index?
    true
  end

  # L11 — search is the list narrowed by title: same check as index?, and the controller reads it
  # through policy_scope, so it shows only what the list would. Test L11-3
  def search?
    index?
  end

  def show?
    return true if support?

    if record.deal_investor.present?
      DealInvestorPolicy.new(user, record.deal_investor).show?
    else
      deal_show_permission?
    end
  end

  def create?
    return true if support?
    return permissioned_rm?(:create) if rm?

    if record.deal_investor.present?
      # D: with a deal investor, the deal itself is checked too (it was not)
      DealInvestorPolicy.new(user, record.deal_investor).update? && parent_in_users_firms?(record.deal)
    else
      deal_update_permission?
    end
  end

  def new?
    create?
  end

  def update?
    return true if support?
    return permissioned_rm?(:update) if rm?

    if record.deal_investor.present?
      DealInvestorPolicy.new(user, record.deal_investor).update?
    else
      deal_update_permission?
    end
  end

  def edit?
    update?
  end

  def toggle_completed?
    update?
  end

  def perform_activity_action?
    update?
  end

  def destroy?
    return true if support?
    return permissioned_rm?(:destroy) if rm?

    if record.deal_investor.present?
      DealInvestorPolicy.new(user, record.deal_investor).destroy?
    else
      deal_update_permission?
    end
  end

  private

  def deal_update_permission?
    return false if record.deal.blank?

    DealPolicy.new(user, record.deal).update?
  end

  def deal_show_permission?
    return false if record.deal.blank?

    DealPolicy.new(user, record.deal).show?
  end
end
