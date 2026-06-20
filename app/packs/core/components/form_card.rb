class FormCard < ViewComponent::Base
  def initialize(title:, controller: "form-validation", css_class: "", header_css_class: "", note: nil)
    super()
    @title = title
    @css_class = css_class
    @header_css_class = header_css_class
    @controller = controller
    @note = note
  end
end
