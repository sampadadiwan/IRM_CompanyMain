module WithNextSteps
  extend ActiveSupport::Concern

  included do
    has_many :tasks, as: :owner, dependent: :destroy
  end

  def generate_next_steps(tag_list: nil, save_step: true)
    # This method should be overridden in the including class
    # It should return an array of next step objects
    next_steps_list = task_templates(tag_list)
    next_step_tasks = []
    return unless next_steps_list

    next_steps_list.each do |task_template|
      task = tasks.build(
        details: task_template.details,
        due_date: Time.zone.today + task_template.due_in_days.days,
        entity_id: entity_id,
        task_template_id: task_template.id
      )
      next_step_tasks << task
    end

    next_step_tasks.each(&:save) if save_step

    next_step_tasks
  end

  private

  def task_templates(tag_list)
    templates = TaskTemplate.where(for_class: self.class.name)
    if tag_list
      tag_list = tag_list.split(",").map(&:strip)
      templates = templates.where(tag_list:)
    end
    templates
  end
end
