json.extract! blog, :id, :title, :tag_list, :body, :created_at, :updated_at
json.url blog_url(blog, format: :json)
