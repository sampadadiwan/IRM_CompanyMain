class ExcercisesController < ApplicationController
  before_action :set_excercise, only: %i[show edit update destroy approve]

  # GET /excercises or /excercises.json
  def index
    @excercises = policy_scope(Excercise).includes(:holding, :user, :option_pool)
    @excercises = @excercises.where(option_pool_id: params[:option_pool_id]) if params[:option_pool_id].present?
  end

  def search
    @entity = current_user.entity
    query = params[:query]
    if query.present?
      @excercises = ExcerciseIndex.filter(term: { entity_id: @entity.id })
                                  .query(query_string: { fields: ExcerciseIndex::SEARCH_FIELDS,
                                                         query:, default_operator: 'and' }).objects
      render "index"
    else
      redirect_to excercises_path
    end
  end

  # GET /excercises/1 or /excercises/1.json
  def show; end

  # GET /excercises/new
  def new
    @excercise = Excercise.new(excercise_params)
    @excercise.user_id = current_user.id
    @excercise.option_pool_id = @excercise.holding.option_pool_id
    @excercise.entity_id = @excercise.holding.entity_id
    @excercise.quantity = @excercise.holding.net_avail_to_excercise_quantity
    @excercise.price = @excercise.option_pool.excercise_price

    authorize(@excercise)
  end

  # GET /excercises/1/edit
  def edit; end

  # POST /excercises or /excercises.json
  def create
    @excercise = Excercise.new(excercise_params)
    @excercise.option_pool_id = @excercise.holding.option_pool_id
    @excercise.entity_id = @excercise.holding.entity_id
    @excercise.user_id = current_user.id
    # For some reason the cents are not directly being taken in
    @excercise.price_cents = excercise_params[:price].to_f * 100
    @excercise.amount_cents = excercise_params[:amount].to_f * 100

    authorize(@excercise)

    respond_to do |format|
      if @excercise.save
        format.html { redirect_to excercise_url(@excercise), notice: "Excercise was successfully created." }
        format.json { render :show, status: :created, location: @excercise }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @excercise.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /excercises/1 or /excercises/1.json
  def update
    @excercise.entity_id = @excercise.holding.entity_id
    @excercise.user_id = current_user.id

    respond_to do |format|
      if @excercise.update(excercise_params)
        format.html { redirect_to excercise_url(@excercise), notice: "Excercise was successfully updated." }
        format.json { render :show, status: :ok, location: @excercise }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @excercise.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /excercises/1 or /excercises/1.json
  def destroy
    @excercise.destroy

    respond_to do |format|
      format.html { redirect_to excercises_url, notice: "Excercise was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  def approve
    @excercise = ApproveExcercise.call(excercise: @excercise).excercise
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.replace(@excercise)
        ]
      end
      format.html { redirect_to excercise_path(@excercise), notice: "Excercise was successfully approved." }
      format.json { @excercise.to_json }
    end
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_excercise
    @excercise = Excercise.find(params[:id])
    authorize(@excercise)
  end

  # Only allow a list of trusted parameters through.
  def excercise_params
    params.require(:excercise).permit(:entity_id, :holding_id, :user_id, :option_pool_id, :quantity, :price, :amount, :tax, :tax_rate, :payment_proof)
  end
end
