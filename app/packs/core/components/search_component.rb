class SearchComponent < ViewComponent::Base
    def initialize(data_source:, turbo_frame:)
        @data_source = data_source
        @turbo_frame = turbo_frame
        puts "SearchComponent#initialize with data_source: #{@data_source}"
    end
end
