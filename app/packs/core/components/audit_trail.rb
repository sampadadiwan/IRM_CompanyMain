class AuditTrail < ViewComponent::Base
  def initialize(model, title: nil, css_class: "", state: "show", allow_toggle: true)
    super
    @model = model
    @title = title
    @css_class = css_class
    @state = state
    @allow_toggle = allow_toggle
  end
end
