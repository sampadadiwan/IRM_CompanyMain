FactoryBot.define do
  factory :ai_chat_message do
    ai_chat_session { nil }
    role { "MyString" }
    content { "MyText" }
  end
end
