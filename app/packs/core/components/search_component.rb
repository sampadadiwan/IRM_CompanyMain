class SearchComponent < ViewComponent::Base
  include SearchHelper
  def initialize(data_source:, turbo_frame:, allow_search: true)
    super
    @data_source = data_source
    @turbo_frame = turbo_frame
    @allow_search = allow_search
  end
end
