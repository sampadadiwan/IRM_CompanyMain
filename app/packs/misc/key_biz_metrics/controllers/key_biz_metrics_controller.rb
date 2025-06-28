class KeyBizMetricsController < ApplicationController
  before_action :set_key_biz_metric, only: %i[show edit update destroy]

  # GET /key_biz_metrics
  def index
    authorize KeyBizMetric
    @q = KeyBizMetric.ransack(params[:q])
    @key_biz_metrics = policy_scope(@q.result)

    @key_biz_metrics = @key_biz_metrics.where(run_date: params[:run_date]) if params[:run_date].present?
    @key_biz_metrics = @key_biz_metrics.where(name: params[:name]) if params[:name].present?
    @key_biz_metrics = @key_biz_metrics.where(metric_type: params[:metric_type]) if params[:metric_type].present?

    @key_biz_metrics = @key_biz_metrics.order(updated_at: :desc)
    page_size = params[:page_size].present? ? params[:page_size].to_i : 12
    @pagy, @key_biz_metrics = pagy(@key_biz_metrics, items: page_size)
  end

  # GET /key_biz_metrics/1
  def show; end

  # GET /key_biz_metrics/new
  def new
    @key_biz_metric = KeyBizMetric.new
    authorize @key_biz_metric
  end

  # GET /key_biz_metrics/1/edit
  def edit; end

  # POST /key_biz_metrics
  def create
    @key_biz_metric = KeyBizMetric.new(key_biz_metric_params)
    authorize @key_biz_metric
    if @key_biz_metric.save
      redirect_to @key_biz_metric, notice: "Key biz metric was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /key_biz_metrics/1
  def update
    if @key_biz_metric.update(key_biz_metric_params)
      redirect_to @key_biz_metric, notice: "Key biz metric was successfully updated.", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /key_biz_metrics/1
  def destroy
    @key_biz_metric.destroy!
    redirect_to key_biz_metrics_url, notice: "Key biz metric was successfully destroyed.", status: :see_other
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_key_biz_metric
    @key_biz_metric = KeyBizMetric.find(params[:id])
    authorize @key_biz_metric
  end

  # Only allow a list of trusted parameters through.
  def key_biz_metric_params
    params.require(:key_biz_metric).permit(:name, :metric_type, :value, :display_value, :notes)
  end
end
