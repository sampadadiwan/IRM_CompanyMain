class SearchComponent < ViewComponent::Base
  include SearchHelper
  def initialize(data_source:, turbo_frame:)
    super
    @data_source = data_source
    @turbo_frame = turbo_frame
  end
end
