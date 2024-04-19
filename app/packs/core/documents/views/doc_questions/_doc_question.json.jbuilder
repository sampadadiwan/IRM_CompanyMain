json.extract! doc_question, :id, :entity_id, :tags, :question, :created_at, :updated_at
json.url doc_question_url(doc_question, format: :json)
