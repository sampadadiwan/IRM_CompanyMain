class AddEsignToExpressionOfInterest < ActiveRecord::Migration[7.0]
  def change
    add_column :expression_of_interests, :esign_required, :boolean, default: false
    add_column :expression_of_interests, :esign_completed, :boolean, default: false
    add_column :expression_of_interests, :properties, :text 
  end
end
