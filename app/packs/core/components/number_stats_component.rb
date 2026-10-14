# app/components/fund_card_component.rb
class NumberStatsComponent < ViewComponent::Base
  def initialize(path:, amount:, subtitle:, progress_bar_color:, fs_size: 5, text_info: nil, css_class: "", css_style: "", raw_amount: nil, tooltip: nil)
    super()
    @path = path
    # Stat cards are narrow: "Crores" / "Lakhs" / "Million" wrap onto a second line, so show Cr / L / M
    @amount = short_units(amount)
    @raw_amount = raw_amount
    @subtitle = subtitle
    @progress_bar_color = progress_bar_color
    @fs_size = fs_size
    @text_info = text_info
    @css_class = css_class
    @css_style = css_style
    # Optional help text: an info icon after the subtitle explains how the figure is worked out
    @tooltip = tooltip
  end

  # "₹383.02 Crores" -> "₹383.02 Cr" (same short forms as money_to_currency(short_units: true))
  def short_units(amount)
    return amount unless amount.is_a?(String)

    # Work on a plain String (sub on a SafeBuffer drops html_safe), then keep the caller's safety
    short = amount.to_str.sub(/\s(crores|lakhs|million)\z/i) { " #{CurrencyHelper::SHORT_UNITS[Regexp.last_match(1).downcase]}" }
    amount.html_safe? ? short.html_safe : short # rubocop:disable Rails/OutputSafety
  end

  attr_reader :path, :amount, :raw_amount, :subtitle, :progress_bar_color, :text_info, :fs_size, :css_class, :css_style, :tooltip
end
