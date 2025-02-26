class RansackTableRow < ViewComponent::Base
  include Ransack::Helpers::FormHelper
  include CurrencyHelper

  def initialize(model:, columns:)
    super
    @columns = columns
    @model = model
  end
end
