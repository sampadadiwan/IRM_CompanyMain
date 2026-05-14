module Noticed
  class NotificationPolicy < ApplicationPolicy
    class Scope < Scope
      def resolve
        if user.curr_role == "investor"
          scope.where(recipient_type: "User", recipient_id: user.id)
        else
          scope.joins(:event).where("JSON_UNQUOTE(JSON_EXTRACT(noticed_events.params, '$.entity_id')) = ?", user.entity_id).or(scope.where(recipient_type: "User", recipient_id: user.id))
        end
      end
    end

    def index?
      !user.investor_advisor?
    end

    def show?
      (user.id == record.recipient_id && record.recipient_type == "User") ||
        permissioned_employee?(:read, owner: record.event.record)
    end

    def mark_as_read?
      user.id == record.recipient_id && record.recipient_type == "User"
    end

    def create?
      false
    end

    def new?
      create?
    end

    def update?
      create?
    end

    def edit?
      update?
    end

    def destroy?
      update?
    end
  end
end
