json.extract! note, :id, :entity_id, :user_id, :investor_id, :created_at, :updated_at
json.url note_url(note, format: :json)
json.user_name note.user.name
json.investor_name note.investor.investor_name
json.details note.details.body
