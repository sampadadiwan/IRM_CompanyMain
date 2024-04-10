# app/components/fund_card_component.rb
class NumberStatsComponent < ViewComponent::Base
  def initialize(path:, amount:, subtitle:, progress_bar_color:, fs_size: 5, text_info: nil)
    super
    @path = path
    @amount = amount
    @subtitle = subtitle
    @progress_bar_color = progress_bar_color
    @fs_size = fs_size
    @text_info = text_info
  end

  attr_reader :path, :amount, :subtitle, :progress_bar_color, :text_info
end
