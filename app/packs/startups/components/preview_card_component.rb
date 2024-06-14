class PreviewCardComponent < ViewComponent::Base
  def initialize(title: "", path: "", model: nil, logo: nil, show_tags: true, col_size: 12)
    super
    @title = title
    @path = path
    @model = model
    @logo = logo || model.entity.logo
    @show_tags = show_tags
    @col_size = col_size
    @tags = model.tags
  end

  attr_accessor :title, :path, :logo, :model, :tags, :show_tags, :col_size
end
