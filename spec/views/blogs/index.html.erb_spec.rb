require 'rails_helper'

RSpec.describe "blogs/index", type: :view do
  before(:each) do
    assign(:blogs, [
      Blog.create!(
        title: "Title",
        tag_list: "Tag List",
        body: "MyText"
      ),
      Blog.create!(
        title: "Title",
        tag_list: "Tag List",
        body: "MyText"
      )
    ])
  end

  it "renders a list of blogs" do
    render
    cell_selector = 'div>p'
    assert_select cell_selector, text: Regexp.new("Title".to_s), count: 2
    assert_select cell_selector, text: Regexp.new("Tag List".to_s), count: 2
    assert_select cell_selector, text: Regexp.new("MyText".to_s), count: 2
  end
end
