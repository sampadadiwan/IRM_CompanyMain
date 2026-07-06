# frozen_string_literal: true

class AddWorkflowTemplateToFolders < ActiveRecord::Migration[7.1]
  def change
    # nullable — most folders have no workflow
    add_reference :folders, :workflow_template, null: true, foreign_key: true
  end
end
