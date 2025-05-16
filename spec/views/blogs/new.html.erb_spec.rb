require 'rails_helper'

RSpec.describe "blogs/new", type: :view do
  before(:each) do
    assign(:blog, Blog.new(
      title: "MyString",
      tag_list: "MyString",
      body: "MyText"
    ))
  end

  it "renders new blog form" do
    render

    assert_select "form[action=?][method=?]", blogs_path, "post" do

      assert_select "input[name=?]", "blog[title]"

      assert_select "input[name=?]", "blog[tag_list]"

      assert_select "textarea[name=?]", "blog[body]"
    end
  end
end
