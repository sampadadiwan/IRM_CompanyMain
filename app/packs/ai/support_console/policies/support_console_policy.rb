# frozen_string_literal: true

# Who may use the Support Console, and about which clients.
#
# The record is the client Entity being asked about (or :support_console for the index).
# A :support user may ask about exactly the clients the admin pages already let them support:
# the :support rule of EntityPolicy::Scope#resolve_admin (an enabled SupportClientMapping, and
# the client's enable_support permission), narrowed by the mapping's end_date, because
# SupportClientMapping.disable_expired only runs on a schedule.
#
# @see openspec/changes/support-console/design.md (card ② Access check)
class SupportConsolePolicy < ApplicationPolicy
  # H2, X1, X2 — only :support users see the console; :super alone is not enough.
  #
  # @return [Boolean]
  def index?
    user.has_cached_role?(:support)
  end

  # H1, E5, E6, E7, E8, X3 — the client must be pickable at the moment of the check.
  #
  # @return [Boolean]
  def ask?
    index? && record.is_a?(Entity) && pickable_entities.exists?(id: record.id)
  end

  alias show? ask?

  # The clients this user may pick.
  #
  # @return [ActiveRecord::Relation<Entity>]
  def pickable_entities
    Scope.new(user, Entity).resolve
  end

  # The clients a user may pick, from the same rule as the admin pages.
  class Scope < Scope
    # @return [ActiveRecord::Relation<Entity>]
    def resolve
      # X1, X2 — nothing for users without the :support role.
      return scope.none unless user.has_cached_role?(:support)

      # The :support branch of EntityPolicy::Scope#resolve_admin, applied even when the user is
      # also :super (whose resolve_admin would return every entity): the console follows mappings.
      # E7 — the client must have enable_support.
      scope.joins(:support_client_mappings)
           .where(support_client_mappings: { user_id: user.id, enabled: true })
           .merge(Entity.where_permissions(:enable_support))
           # E6 — an end date in the past closes access even before disable_expired has run;
           # E5 — an end date of today is still open.
           .where("support_client_mappings.end_date IS NULL OR support_client_mappings.end_date >= ?", Time.zone.today)
           .distinct
    end
  end
end
