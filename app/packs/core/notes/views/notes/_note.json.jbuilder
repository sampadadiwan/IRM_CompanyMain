json.extract! note, :id, :entity_id, :user_id, :created_at, :updated_at
json.url note_url(note, format: :json)
json.user_name note.user.name
json.investor_name(note.to_s)
json.details note.details.body
