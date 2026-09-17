# Side letter records on capital commitments: manual creation (pick the
# executed PDF from the commitment's documents), review overview, and the
# jumping-off point for manual obligation entry.
class SideLettersController < ApplicationController
  before_action :set_side_letter, only: %i[show edit update destroy]

  def index
    authorize SideLetter
    @bread_crumbs = { "Side Letters": side_letters_path }
    @side_letters = policy_scope(SideLetter)
                    .includes(:document, :side_letter_obligations, capital_commitment: %i[investor fund])
                    .order(created_at: :desc)
    @side_letters = @side_letters.where(capital_commitment_id: params[:capital_commitment_id]) if params[:capital_commitment_id].present?
  end

  def show
    # Layout breadcrumb card (layouts/_breadcrumbs): Home • Side Letters • Investor • Document
    @bread_crumbs = {
      "Side Letters": side_letters_path,
      "#{@side_letter.capital_commitment.investor_name}": capital_commitment_path(@side_letter.capital_commitment),
      "#{@side_letter.document.name}": side_letter_path(@side_letter)
    }
    @obligations = @side_letter.side_letter_obligations
                               .includes(:owner_user)
                               .order(Arel.sql("next_due_date IS NULL, next_due_date ASC"))
    # All projected covenant tasks across this side letter's obligations —
    # tasks are owned by the obligation (so completion records fulfillment),
    # which is why they don't appear in commitment-owned task lists.
    @covenant_tasks = Task.where(owner_type: "SideLetterObligation", owner_id: @obligations.map(&:id))
                          .includes(:assigned_to)
                          .order(Arel.sql("completed ASC, due_date IS NULL, due_date ASC"))
  end

  def new
    @side_letter = SideLetter.new(capital_commitment_id: params[:capital_commitment_id])
    @side_letter.entity_id = current_user.entity_id
    authorize @side_letter
  end

  def create
    @side_letter = SideLetter.new(side_letter_params)
    @side_letter.entity_id = current_user.entity_id
    # Manual creation implies the obligations will be typed in by hand
    @side_letter.extraction_status = "manually_entered"
    authorize @side_letter

    if @side_letter.save
      redirect_to side_letter_path(@side_letter), notice: "Side letter was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @side_letter.update(side_letter_params)
      redirect_to side_letter_path(@side_letter), notice: "Side letter was successfully updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @side_letter.destroy
    redirect_to side_letters_path, notice: "Side letter was deleted."
  end

  private

  def set_side_letter
    @side_letter = SideLetter.find(params[:id])
    authorize @side_letter
  end

  def side_letter_params
    params.require(:side_letter).permit(:capital_commitment_id, :document_id, :executed_at, :notes)
  end
end
