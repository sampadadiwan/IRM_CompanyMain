class OptionPoolsController < ApplicationController
  before_action :set_option_pool, only: %i[show edit update destroy approve]

  # GET /option_pools or /option_pools.json
  def index
    @option_pools = policy_scope(OptionPool).includes(:entity)
  end

  # GET /option_pools/1 or /option_pools/1.json
  def show; end

  # GET /option_pools/new
  def new
    @option_pool = OptionPool.new
    @option_pool.start_date = Time.zone.today
    @option_pool.entity_id = current_user.entity_id
    (1..4).each do |i|
      @option_pool.vesting_schedules.build(months_from_grant: i * 12, vesting_percent: 25)
    end

    # Custom form fields
    form_type = FormType.where(entity_id: current_user.entity_id, name: "OptionPool").first
    @option_pool.form_type = form_type

    authorize(@option_pool)
  end

  # GET /option_pools/1/edit
  def edit; end

  # POST /option_pools or /option_pools.json
  def create
    @option_pool = OptionPool.new(option_pool_params)
    @option_pool.entity_id = current_user.entity_id
    @option_pool.excercise_price_cents = option_pool_params[:excercise_price].to_f * 100

    authorize(@option_pool)

    @option_pool = CreateOptionPool.call(option_pool: @option_pool).option_pool

    respond_to do |format|
      if @option_pool.errors.any?
        Rails.logger.debug @option_pool.to_json(include: :vesting_schedules)
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @option_pool.errors, status: :unprocessable_entity }
      else
        format.html { redirect_to option_pool_url(@option_pool), notice: "Option pool was successfully created." }
        format.json { render :show, status: :created, location: @option_pool }
      end
    end
  end

  # PATCH/PUT /option_pools/1 or /option_pools/1.json
  def update
    respond_to do |format|
      if @option_pool.update(option_pool_params)
        format.html { redirect_to option_pool_url(@option_pool), notice: "Option pool was successfully updated." }
        format.json { render :show, status: :ok, location: @option_pool }
      else
        Rails.logger.debug @option_pool.to_json(include: :vesting_schedules)
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @option_pool.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /option_pools/1 or /option_pools/1.json
  def destroy
    @option_pool.destroy

    respond_to do |format|
      format.html { redirect_to option_pools_url, notice: "Option pool was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  def approve
    @option_pool = ApproveOptionPool.call(option_pool: @option_pool).option_pool
    respond_to do |format|
      if @option_pool.save
        format.html do
          redirect_to option_pool_path(@option_pool),
                      notice: "Option pool was successfully approved."
        end
        format.json { render :show, status: :created, location: @option_pool }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @option_pool.errors, status: :unprocessable_entity }
      end
    end
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_option_pool
    @option_pool = OptionPool.find(params[:id])
    authorize(@option_pool)
  end

  # Only allow a list of trusted parameters through.
  def option_pool_params
    params.require(:option_pool).permit(:name, :start_date, :number_of_options, :excercise_price,
                                        :excercise_period_months, :entity_id, :funding_round_id, :certificate_signature, :manual_vesting, :details, :form_type_id,
                                        attachments: [], excercise_instructions: [], properties: {},
                                        vesting_schedules_attributes: %i[id months_from_grant vesting_percent _destroy])
  end
end
