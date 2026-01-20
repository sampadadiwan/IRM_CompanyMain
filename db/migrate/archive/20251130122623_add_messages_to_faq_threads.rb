class AddMessagesToFaqThreads < ActiveRecord::Migration[8.0]
  def change
    add_column :faq_threads, :messages, :json
  end
end
