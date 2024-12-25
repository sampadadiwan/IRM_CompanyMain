# app/components/widget_card_component.rb

class WidgetCardComponent < ViewComponent::Base
  def initialize(widget:, widget_size: nil, name: nil, args: {})
    @widget = widget
    @widget_size = widget_size || widget.widget_size
    @name = name || widget.widget_name
    @args = args
  end
end
