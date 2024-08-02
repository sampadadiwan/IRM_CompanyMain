class PageCount < ViewComponent::Base
  def initialize(objects)
    super
    @objects = objects
  end
end
