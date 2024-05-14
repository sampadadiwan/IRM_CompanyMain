class OffcanvasComponent < ViewComponent::Base
  def initialize(title: "", offcanvas_id: "")
    super
    @title = title
    @offcanvas_id = offcanvas_id
  end
end
