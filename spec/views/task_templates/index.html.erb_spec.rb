require 'rails_helper'

RSpec.describe "task_templates/index", type: :view do
  before(:each) do
    assign(:task_templates, [
      TaskTemplate.create!(
        details: "MyText",
        due_in_days: 2,
        action_link: "Action Link",
        help_link: "Help Link",
        sequence: 3,
        entity: nil
      ),
      TaskTemplate.create!(
        details: "MyText",
        due_in_days: 2,
        action_link: "Action Link",
        help_link: "Help Link",
        sequence: 3,
        entity: nil
      )
    ])
  end

  it "renders a list of task_templates" do
    render
    cell_selector = 'div>p'
    assert_select cell_selector, text: Regexp.new("MyText".to_s), count: 2
    assert_select cell_selector, text: Regexp.new(2.to_s), count: 2
    assert_select cell_selector, text: Regexp.new("Action Link".to_s), count: 2
    assert_select cell_selector, text: Regexp.new("Help Link".to_s), count: 2
    assert_select cell_selector, text: Regexp.new(3.to_s), count: 2
    assert_select cell_selector, text: Regexp.new(nil.to_s), count: 2
  end
end
