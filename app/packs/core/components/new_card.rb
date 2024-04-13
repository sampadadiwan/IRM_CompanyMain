class NewCard < ViewComponent::Base
  def initialize(col_md: "col-md-6")
    super
    @col_md = col_md
  end
end
