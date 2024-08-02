class FormCard < ViewComponent::Base
  def initialize(title:, controller: "form-validation", css_class: "", header_css_class: "")
    super
    @title = title
    @css_class = css_class
    @header_css_class = header_css_class
    @controller = controller
  end
end
