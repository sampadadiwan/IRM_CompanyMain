class PreviewCardComponent < ViewComponent::Base
  def initialize(title: "", path: "", model: nil, object: nil, logo: nil)
    super
    @title = title
    @path = path
    @model = model
    @object = object
    @logo = logo || model.entity.logo

    @show_tags = true
    @col_size = 12
    @tags = model.tags
  end

  attr_accessor :title, :path, :logo, :model, :object, :tags, :show_tags, :col_size
end
