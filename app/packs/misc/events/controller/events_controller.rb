class EventsController < ApplicationController
  before_action :set_owner, except: %i[show edit]
  before_action :set_event, only: %i[show edit update]

  def index
    @view = params[:view] || 'month'
    @q = Event.ransack(params[:q])
    case @view
    when 'week'
      handle_week_view
    when 'day'
      handle_day_view
    else
      handle_month_view
    end
  end

  def new
    start_time = Time.zone.parse(params[:date])

    start_time = Time.zone.parse("#{params[:date]} #{params[:time_slot]}:00") if params[:time_slot].present?

    @event = Event.new(entity_id: current_user.entity_id)
    @event.start_time = start_time
    @event.end_time = start_time + 1.hour

    authorize @event
  end

  def create
    parsed_start_time = Time.zone.parse(event_params[:start_time])
    parsed_end_time = Time.zone.parse(event_params[:end_time])

    @event = Event.new(event_params.merge(start_time: parsed_start_time, end_time: parsed_end_time))
    @event.owner = @owner
    @event.entity_id = current_user.entity_id

    authorize @event

    if @event.save
      redirect_to @event, notice: 'Event was successfully created.'
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @event.update(event_params)
      redirect_to event_path(@event), notice: 'Event was successfully updated.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def show; end

  def edit; end

  private

  def set_date_ranges
    @current_month = params[:month].present? ? Date.parse("#{params[:month]}-01") : Time.zone.today.beginning_of_month
    @previous_month = @current_month.prev_month
    @next_month = @current_month.next_month
  end

  def view_type
    params[:view] || 'month' # Default to month if no view type is specified
  end

  def handle_month_view
    @current_month = params[:month].present? ? Date.parse("#{params[:month]}-01") : Time.zone.today.beginning_of_month
    @previous_month = @current_month.prev_month
    @next_month = @current_month.next_month

    first_day_of_month = @current_month.beginning_of_month
    first_day_of_week = first_day_of_month.beginning_of_week(:sunday)
    @start_date = first_day_of_week
    @end_date = @current_month.end_of_month.end_of_week(:sunday)

    @events = if @owner
                policy_scope(@q.result).where(owner_id: @owner.id, owner_type: @owner.class.name)
                                       .where('DATE(events.start_time) BETWEEN ? AND ?', @start_date, @end_date)
                                       .order(:start_time)
              else
                policy_scope(@q.result).where('DATE(events.start_time) BETWEEN ? AND ?', @start_date, @end_date)
                                       .order(:start_time)
              end
    @events_by_day = @events.group_by { |event| event.start_time.to_date }
  end

  def handle_week_view
    @current_week = params[:week].present? ? Date.parse(params[:week]) : Time.zone.today.beginning_of_week(:sunday)
    @start_date = @current_week.beginning_of_week(:sunday)
    @end_date = @current_week.end_of_week(:sunday)

    @events = if @owner
                policy_scope(@q.result).where(owner_id: @owner.id, owner_type: @owner.class.name)
                                       .where('DATE(events.start_time) BETWEEN ? AND ?', @start_date, @end_date)
                                       .order(:start_time)
              else
                policy_scope(@q.result).where('DATE(events.start_time) BETWEEN ? AND ?', @start_date, @end_date)
                                       .order(:start_time)
              end
    @events_by_day_and_hour = @events.group_by { |event| [event.start_time.to_date, event.start_time.hour] }

    @previous_week = @current_week - 1.week
    @next_week = @current_week + 1.week
  end

  def handle_day_view
    @current_day = params[:day].present? ? Date.parse(params[:day]) : Time.zone.today
    @start_date = @current_day.beginning_of_day
    @end_date = @current_day.end_of_day

    @events = if @owner
                policy_scope(@q.result).where(owner_id: @owner.id, owner_type: @owner.class.name)
                                       .where('DATE(events.start_time) = ?', @current_day)
                                       .order(:start_time)
              else
                policy_scope(@q.result).where('DATE(events.start_time) = ?', @current_day)
                                       .order(:start_time)
              end
    @events_by_hour = @events.group_by { |event| event.start_time.hour }
  end

  def set_owner
    owner_type = params.dig(:event, :owner_type) || params[:owner_type]
    owner_id = params.dig(:event, :owner_id) || params[:owner_id]
    owner_type = owner_type&.singularize&.camelize

    if owner_type.blank?
      @owner = @current_user.entity
      owner_type = "Entity"
    else
      @owner = owner_type.constantize.find(owner_id)
    end

    authorize @owner unless owner_type == "Entity"
  rescue Pundit::AuthorizationNotPerformedError
    skip_authorization if owner_type == "Entity"
  end

  def set_event
    @event = Event.find(params[:id])
    owner_path = polymorphic_path(@event.owner_type.to_s.underscore.pluralize.downcase)
    @bread_crumbs = { "#{@event.owner_type&.to_s&.pluralize}": owner_path, "#{@event.title}": event_path(@event) }
    authorize @event
  end

  def event_params
    params.require(:event).permit(:owner_type, :owner_id, :title, :description, :start_time, :end_time)
  end
end
