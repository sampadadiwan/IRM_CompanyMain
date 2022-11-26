class AddCommentToExpressionOfInterest < ActiveRecord::Migration[7.0]
  def change
    add_column :expression_of_interests, :comment, :text
  end
end
