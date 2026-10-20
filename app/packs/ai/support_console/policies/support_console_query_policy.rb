# frozen_string_literal: true

# The Support Console's query record is reviewed by CapHive super users only; support users
# never see it, and nobody edits it (rows are append-only).
#
# @see openspec/changes/support-console/design.md (card ⑧ Query record and alerts)
class SupportConsoleQueryPolicy < ApplicationPolicy
  def index?
    super_user?
  end

  def show?
    super_user?
  end

  # Super users see every row; everyone else nothing.
  class Scope < Scope
    def resolve
      user.has_cached_role?(:super) ? scope.all : scope.none
    end

    # Administrate's Punditize prefers resolve_admin when a scope defines it.
    def resolve_admin
      resolve
    end
  end
end
