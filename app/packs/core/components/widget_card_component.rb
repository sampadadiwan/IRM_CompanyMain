# app/components/widget_card_component.rb

class WidgetCardComponent < ViewComponent::Base
  def initialize(widget:, widget_size: nil, name: nil, args: {}, html_options: {}, no_card: false)
    super()
    @widget = widget
    @widget_size = widget_size || widget.widget_size
    @name = name || widget.widget_name
    @args = args
    @html_options = html_options
    @no_card = no_card || args[:no_card] || false
    @collapsible = args[:collapsible] || false
    @maximizable = args[:maximizable] || false
    @preview = args[:preview] || false
  end
end
