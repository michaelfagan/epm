class EventsController < ApplicationController
 
  load_and_authorize_resource :event

  def index
    if current_user.has_role?(:admin) || current_user.has_role?(:coordinator)
      @coordinatorless = Event.coordinatorless.not_past.not_cancelled
      @dateless = Event.dateless.not_cancelled
    end
    @joinable = Event.participatable.not_past.not_attended_by(current_user).limit(10)
  end

  def calendar
    @events = Event.not_cancelled.in_month params['year'], params['month']
  end

  def show
  end

  def new
    attrs = {status: :approved}
    attrs[:start] = params['start_day'] if params['start_day']
    @event = Event.new(attrs)
  end

  def edit
    @event.notify_of_changes = true
  end

  def create
    @event = Event.new event_params
    if @event.save
      if @event.coordinator && @event.coordinator != current_user
        EventMailer.coordinator_assigned(@event).deliver
      end
      redirect_to @event, notice: 'Event saved.'
    else
      render :new
    end
  end

  def update
    event_was_past = @event.past?
    @event.assign_attributes event_params
    users = @event.users.reject{|u| u == current_user}
    new_coordinator = @event.coordinator_id_changed? && @event.coordinator
    changed_significantly = @event.changed_significantly?
    notes_changed = @event.notes_changed?
    if @event.save
      # send email notifications if appropriate
      unless @event.cancelled?
        # alert coordinator being assigned
        if new_coordinator && @event.coordinator != current_user
          users.reject!{|u| u == @event.coordinator} # prevents emailing a coordinator twice when they are assigned an event which has significant changes
          EventMailer.coordinator_assigned(@event).deliver
        end
        # alert other attendees
        if @event.notify_of_changes.present? && !(@event.past? && event_was_past) && users.any?
          users = users.partition{|u| u.ability.can?(:read_notes, @event)} # .first can read the note, .last can't
          if (changed_significantly || notes_changed) && users.first.any?
            EventMailer.change(@event, users.first).deliver
          end
          if changed_significantly && users.last.any?
            EventMailer.change(@event, users.last).deliver
          end
        end
      end
      redirect_to @event, notice: 'Event saved.'
    else
      render :edit
    end
  end

  def approve
    if @event.proposed?
      @event.update(status: :approved)
      flash[:notice] = 'Event approved.'
    else
      flash[:notice] = 'Cannot approve cancelled events.'
    end
    redirect_to @event
  end

  def destroy
    @event.update(status: :cancelled)
    users = @event.users.reject{|u| u == current_user}
    EventMailer.cancel(@event, users).deliver if users.any?
    redirect_to @event, notice: 'Event cancelled.'
  end

  def attend
    if @event.event_users.create user: current_user # this will fail if already attending but that's fine
      EventMailer.attend(@event, current_user).deliver
    end
    redirect_to @event, notice: 'You are now attending this event.'
  end

  def unattend
    # if user is already not attending this event, it does nothing and shows the same message which is fine
    @event.event_users.where(user: current_user).destroy_all
    redirect_to @event, notice: 'You are no longer attending this event.'
  end

  private

    def event_params
      # should actually only enable :status to be set by admin. todo
      params.require(:event).permit(:name, :description, :notes, :start, :start_day, :start_time, :duration, :finish, :coordinator_id, :notify_of_changes, :status)
    end

end