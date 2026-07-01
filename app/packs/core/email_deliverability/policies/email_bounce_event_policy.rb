# frozen_string_literal: true

class EmailBounceEventPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      if user.support?
        scope.all
      else
        scope.where(entity_id: user.entity_id)
      end
    end
  end

  def index?
    true
  end

  def disable_recipient_email?
    support? || belongs_to_entity?(user, record)
  end
end
