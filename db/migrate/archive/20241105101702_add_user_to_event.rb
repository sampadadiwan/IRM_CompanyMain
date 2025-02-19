class AddUserToEvent < ActiveRecord::Migration[7.1]
  def change
    add_reference :events, :user, null: false, foreign_key: true, default: 21
    Event.all.each do |event|
      event.update(user_id: event.entity.employees.first.id) 
    end
  end
end
