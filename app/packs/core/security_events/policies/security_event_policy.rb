# frozen_string_literal: true

# Who may read the security event trail, and which firms' rows (OWASP review 2026-11 M11, design card ⑥, D7).
#
#   super          — every row, including events with no firm (unknown emails, system-wide switches) (E45)
#   support        — the firms whose support mapping is enabled AND which have support switched on, the same rule
#                    as every support scope (BaseScope#resolve_admin); a firm that turns support off drops out (X10)
#   company admin  — their own firm's rows (H29); a NULL-firm row is never theirs
#   anyone else    — refused (employees, approvers, investors, advisors: X6, X7). Approvers are the role most worth
#                    watching, so they don't see the watch; their admins do.
# A support user signed in as a client is judged as that client (the policy sees current_user).
#
# entity_id is deliberately not ransackable (SecurityEvent.ransackable_attributes): this scope is the only tenant
# filter, so a crafted q[entity_id_eq] is ignored (X8) and the download job re-applies it (X9).
class SecurityEventPolicy < ApplicationPolicy
  class Scope < BaseScope
    def resolve
      if user.has_cached_role?(:super)
        # E45 — all firms and the CapHive-only rows
        scope.all
      elsif user.has_cached_role?(:support)
        # E45 / X10 — mapped firms that still let support in
        scope.where(entity_id: SecurityEventPolicy.supported_entity_ids(user))
      elsif user.has_cached_role?(:company_admin)
        # H29 — own firm only
        scope.where(entity_id: user.entity_id)
      else
        # X6 / X7
        scope.none
      end
    end
  end

  # One subquery: the support user's enabled mappings, to firms with the enable_support permission (the
  # BaseScope#resolve_admin rule). Also used by the screen to decide which user names link to a user page.
  # @return [ActiveRecord::Relation] selecting entity_id
  def self.supported_entity_ids(user)
    SupportClientMapping.where(user_id: user.id, enabled: true)
                        .joins(:entity).merge(Entity.where_permissions(:enable_support))
                        .select(:entity_id)
  end

  # The menu entry, the screen and the download
  def index?
    user.has_cached_role?(:super) || user.has_cached_role?(:support) || user.has_cached_role?(:company_admin)
  end
end
