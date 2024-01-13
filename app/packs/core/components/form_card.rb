class FormCard < ViewComponent::Base
  def initialize(title:, css_class: "")
    super
    @title = title
    @css_class = css_class
  end
end
