# frozen_string_literal: true

class FormCard < ViewComponent::Base
  def initialize(title:)
    super
    @title = title
  end
end
