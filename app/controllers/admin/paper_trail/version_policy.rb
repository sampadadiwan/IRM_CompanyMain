module PaperTrail
  class VersionPolicy < ApplicationPolicy
    class Scope < Scope
      def resolve
        scope.none
      end
    end
  end
end
