module PaperTrail
  class VersionPolicy < ApplicationPolicy
    class Scope < Scope
      def resolve
        scope.none
      end
    end

    def index?
      true
    end

    def show?
      true
    end
  end
end
