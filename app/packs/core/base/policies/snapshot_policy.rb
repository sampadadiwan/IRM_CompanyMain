# app/policies/concerns/snapshot_policy.rb
module SnapshotPolicy
  extend ActiveSupport::Concern

  included do
    def create?
      false
    end

    def edit?
      false
    end

    def update?
      false
    end

    def edit?
      false
    end

    def destroy?
      false
    end
  end
end
