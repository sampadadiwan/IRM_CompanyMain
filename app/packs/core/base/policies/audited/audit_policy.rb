module Audited
  class AuditPolicy < ApplicationPolicy
    class Scope < Scope
      # NOTE: Be explicit about which records you allow access to!
      # def resolve
      #   scope.all
      # end
    end

    def index?
      super_user?
    end

    def show?
      true
    end
  end
end
