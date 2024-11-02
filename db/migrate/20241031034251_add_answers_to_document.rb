class AddAnswersToDocument < ActiveRecord::Migration[7.1]
  def change
    add_column :documents, :qna, :text
  end
end
