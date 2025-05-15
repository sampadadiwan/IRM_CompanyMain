require 'rails_helper'

RSpec.describe "task_templates/show", type: :view do
  before(:each) do
    assign(:task_template, TaskTemplate.create!(
      details: "MyText",
      due_in_days: 2,
      action_link: "Action Link",
      help_link: "Help Link",
      sequence: 3,
      entity: nil
    ))
  end

  it "renders attributes in <p>" do
    render
    expect(rendered).to match(/MyText/)
    expect(rendered).to match(/2/)
    expect(rendered).to match(/Action Link/)
    expect(rendered).to match(/Help Link/)
    expect(rendered).to match(/3/)
    expect(rendered).to match(//)
  end
end
