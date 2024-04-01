# app/components/fund_card_component.rb
class NumberStatsComponent < ViewComponent::Base
  def initialize(path:, amount:, subtitle:, progress_bar_color:)
    super
    @path = path
    @amount = amount
    @subtitle = subtitle
    @progress_bar_color = progress_bar_color
  end

  attr_reader :path, :amount, :subtitle, :progress_bar_color
end
