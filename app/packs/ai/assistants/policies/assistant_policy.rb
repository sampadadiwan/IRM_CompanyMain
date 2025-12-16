class AssistantPolicy < ApplicationPolicy
  def show?
    true
  end

  def ask?
    show?
  end

  def transcribe?
    show?
  end
end
