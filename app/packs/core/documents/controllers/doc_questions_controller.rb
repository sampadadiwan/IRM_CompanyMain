class DocQuestionsController < ApplicationController
  before_action :set_doc_question, only: %i[show edit update destroy]

  # GET /doc_questions or /doc_questions.json
  def index
    authorize DocQuestion
    @doc_questions = policy_scope(DocQuestion)
  end

  # GET /doc_questions/1 or /doc_questions/1.json
  def show; end

  # GET /doc_questions/new
  def new
    @doc_question = DocQuestion.new(doc_question_params)
    @doc_question.entity_id = current_user.entity_id
    @doc_question.owner ||= current_user.entity
    authorize @doc_question
  end

  # GET /doc_questions/1/edit
  def edit; end

  # POST /doc_questions or /doc_questions.json
  def create
    @doc_question = DocQuestion.new(doc_question_params)
    @doc_question.entity_id = current_user.entity_id
    authorize @doc_question

    respond_to do |format|
      if @doc_question.save
        format.html { redirect_to doc_question_url(@doc_question), notice: "Doc question was successfully created." }
        format.json { render :show, status: :created, location: @doc_question }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @doc_question.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /doc_questions/1 or /doc_questions/1.json
  def update
    respond_to do |format|
      if @doc_question.update(doc_question_params)
        format.html { redirect_to doc_question_url(@doc_question), notice: "Doc question was successfully updated." }
        format.json { render :show, status: :ok, location: @doc_question }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @doc_question.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /doc_questions/1 or /doc_questions/1.json
  def destroy
    @doc_question.destroy!

    respond_to do |format|
      format.html { redirect_to doc_questions_url, notice: "Doc question was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_doc_question
    @doc_question = DocQuestion.find(params[:id])
    authorize @doc_question
    @bread_crumbs = { Questions: doc_questions_path, "#{@doc_question}": nil }
  end

  # Only allow a list of trusted parameters through.
  def doc_question_params
    params.require(:doc_question).permit(:entity_id, :tags, :question, :document_name, :for_class, :qtype, :owner_id, :owner_type, :response_hint)
  end
end
