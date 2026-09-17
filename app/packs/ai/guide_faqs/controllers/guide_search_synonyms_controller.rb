# frozen_string_literal: true

# Search synonyms for the chatbot's guide search. Saving any rule rebuilds the search index in
# the background (GuideSearchReindexJob).
class GuideSearchSynonymsController < ApplicationController
  before_action :set_synonym, only: %i[edit update destroy]

  def index
    authorize GuideSearchSynonym
    @synonyms = policy_scope(GuideSearchSynonym).order(:terms)
  end

  def new
    @synonym = GuideSearchSynonym.new
    authorize @synonym
  end

  def edit; end

  def create
    @synonym = GuideSearchSynonym.new(synonym_params.merge(updated_by: current_user))
    authorize @synonym
    if @synonym.save
      redirect_to guide_search_synonyms_path, notice: "Synonym saved. Search picks it up within a few minutes."
    else
      render :new, status: :unprocessable_content
    end
  end

  def update
    if @synonym.update(synonym_params.merge(updated_by: current_user))
      redirect_to guide_search_synonyms_path, notice: "Synonym updated. Search picks it up within a few minutes."
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @synonym.destroy!
    redirect_to guide_search_synonyms_path, notice: "Synonym deleted."
  end

  private

  def set_synonym
    @synonym = GuideSearchSynonym.find(params[:id])
    authorize @synonym
  end

  def synonym_params
    params.expect(guide_search_synonym: %i[terms enabled note])
  end
end
