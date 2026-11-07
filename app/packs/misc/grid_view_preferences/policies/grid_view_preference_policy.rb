class GridViewPreferencePolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      scope.where(entity_id: user.entity_id)
    end
  end

  # M15 — a column hangs off its owner (a Report or FormType): the owner must be in the user's firms
  # too, since the column's own entity_id is only copied from it. Company admins only, as before.
  # Worked examples M15-3, M15-H — docs/security/security_review_2026_10.md#core--misc--medium-and-low
  def create?
    belongs_to_entity?(user, record) && parent_in_users_firms?(record.owner) && user.has_cached_role?(:company_admin)
  end

  # M15 — opening Configure Grid for an owner: any user of the owner's firm (the Decision kept it open
  # to non-admins); the screen lists the owner's columns and custom fields (M15-4, M15-H)
  def configure_grids?
    belongs_to_entity?(user, record) && parent_in_users_firms?(record.owner)
  end

  # The columns icon and side panel on a table (openspec/changes/grid-columns-inline-settings — D11): whoever may
  # save columns for the owner (company admin of its firm), never a user acting as an investor (X2), and for a
  # report's own columns only someone who may edit that report (X7, parent-policy delegation). The record is an
  # unsaved column for the owner, as configure_grids builds it; a new FormType owner carries the firm (H4).
  def inline_columns?
    # X1, X3 — firm + company admin; X2 — not acting as an investor
    return false unless create? && !user.curr_role_investor?

    # X7 — a report's columns need the right to edit the report
    record.owner.is_a?(Report) ? new_policy(record.owner).update? : true
  end

  def show?
    create?
  end

  def edit?
    create?
  end

  def update?
    create?
  end

  def destroy?
    create?
  end

  def update_column_sequence?
    create?
  end

  def new?
    create?
  end
end
