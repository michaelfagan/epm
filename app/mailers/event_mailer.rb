class EventMailer < ActionMailer::Base

  default from: "#{Configurable.title} <#{Configurable.email}>"

  # in many of these methods, @user is for checking permissions -
  #   usually passing in an array of users who all have the same permissions so can just use the first

  def attend(event, users)
    users = [*users] # enables inputting a single user or array of users
    @event = event
    # users are all participants, but as some could be an admin, need to do this for permissions:
    @user = users.find{|u| u.ability.cannot?(:read_notes, event)} || users.first
    mail bcc: users.map{|u| to(u)}, subject: 'You are attending an event'
  end

  def coordinator_assigned(event)
    @event = event
    mail to: to(@event.coordinator), subject: 'You have been assigned an event'
  end

  def cancel(event, users)
    @event = event
    @user = users.first
    mail bcc: users.map{|u| to(u)}, subject: "#{@event.display_name} has been cancelled"
  end

  def change(event, users)
    @event = event
    @user = users.first
    mail bcc: users.map{|u| to(u)}, subject: 'Changes to an event you are attending'
  end

  def awaiting_approval(event, users)
    @event = event
    @user = users.first
    mail bcc: users.map{|u| to(u)}, subject: 'An event is awaiting approval'
  end

  def approve(event)
    @event = event
    mail to: to(event.coordinator), subject: 'Your event has been approved'
  end

  private

    def to(user)
      user.name.present? ? "#{user.name} <#{user.email}>" : user.email
    end

end
