class AddFormTypeIdToExpressionOfInterests < ActiveRecord::Migration[8.0]
  def change
    unless column_exists? :expression_of_interests, :form_type_id
      add_reference :expression_of_interests, :form_type, foreign_key: true
    end
  end
end
