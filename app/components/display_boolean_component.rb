# frozen_string_literal: true

class DisplayBooleanComponent < ViewComponent::Base
  def initialize(bool:)
    super
    @bool = bool
  end
end
