class EditModalComponent < ViewComponent::Base
  def initialize(title: "", modal_id: "")
    super
    @title = title
    @modal_id = modal_id
  end
end
