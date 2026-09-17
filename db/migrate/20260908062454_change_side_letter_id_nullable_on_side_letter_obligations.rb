# frozen_string_literal: true

# Allow side_letter_id to be NULL for portfolio investment obligations,
# which use the polymorphic sourceable association instead.
class ChangeSideLetterIdNullableOnSideLetterObligations < ActiveRecord::Migration[8.1]
  def change
    change_column_null :side_letter_obligations, :side_letter_id, true
  end
end
