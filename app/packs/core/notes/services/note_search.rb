class NoteSearch
  def self.perform(notes, current_user, params)
    notes = notes.where(id: search_ids(params, current_user)) if params[:search] && params[:search][:value].present?
    notes
  end

  def self.search_ids(params, current_user)
    query = "#{params[:search][:value]}*"
    entity_ids = [current_user.entity_id]

    NoteIndex.filter(terms: { entity_id: entity_ids })
             .query(query_string: { fields: NoteIndex::SEARCH_FIELDS, query:, default_operator: 'and' })
             .per(1000)
             .map(&:id)
  end
end
