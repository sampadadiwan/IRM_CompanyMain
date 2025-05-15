require 'rails_helper'

RSpec.describe "task_templates/edit", type: :view do
  let(:task_template) {
    TaskTemplate.create!(
      details: "MyText",
      due_in_days: 1,
      action_link: "MyString",
      help_link: "MyString",
      sequence: 1,
      entity: nil
    )
  }

  before(:each) do
    assign(:task_template, task_template)
  end

  it "renders the edit task_template form" do
    render

    assert_select "form[action=?][method=?]", task_template_path(task_template), "post" do

      assert_select "textarea[name=?]", "task_template[details]"

      assert_select "input[name=?]", "task_template[due_in_days]"

      assert_select "input[name=?]", "task_template[action_link]"

      assert_select "input[name=?]", "task_template[help_link]"

      assert_select "input[name=?]", "task_template[sequence]"

      assert_select "input[name=?]", "task_template[entity_id]"
    end
  end
end
