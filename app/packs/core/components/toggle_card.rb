class ToggleCard < ViewComponent::Base
  def initialize(title:, css_class: "", controller: nil, state: "show", allow_toggle: true)
    super
    @title = title
    # Any additional css classes to be attached to the card
    @css_class = css_class
    # Anay data-controller to be attached to the card
    @controller = controller
    # The state of the card, either "show" or "hide"
    @state = state
    # Whether the card can be toggled or not
    @allow_toggle = allow_toggle
  end
end
