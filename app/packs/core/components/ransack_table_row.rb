class RansackTableRow < ViewComponent::Base
  include Ransack::Helpers::FormHelper

  def initialize(model:, columns:)
    super
    @columns = columns
    @model = model
  end
end
