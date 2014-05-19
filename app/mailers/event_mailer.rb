class EventMailer < ActionMailer::Base

  default from: "#{Configurable.title} <#{Configurable.email}>"

  # in many of these methods, @user is for checking permissions -
  #   usually passing in an array of users who all have the same permissions so can just use the first

  def attend(event, users)
    users = [*users]
    @event = event
    # users are all participants, but as some could also be admins, need to do this for permissions:
    @user = users.find{|u| u.ability.cannot?(:read_notes, event)} || users.first
    mail bcc: to(users), subject: 'You are attending an event'
  end

  def unattend(event, users, reason = nil)
    @event = event
    @reason = reason
    mail bcc: to(users), subject: "You are no longer attending #{event.display_name}"
  end

  def coordinator_assigned(event)
    @event = event
    mail to: to(@event.coordinator), subject: 'You have been assigned an event'
  end

  def cancel(event, users)
    @event = event
    @user = users.first
    mail bcc: to(users), subject: "#{@event.display_name} has been cancelled"
  end

  def change(event, users)
    @event = event
    @user = users.first
    mail bcc: to(users), subject: 'Changes to an event you are attending'
  end

  def awaiting_approval(event, users)
    @event = event
    @user = users.first
    mail bcc: to(users), subject: 'An event is awaiting approval'
  end

  def approve(event)
    @event = event
    mail to: to(event.coordinator), subject: 'Your event has been approved'
  end

  def invite(event, users)
    @event = event
    users = [*users]
    # users are all participants, but as some could also be admins, need to do this for permissions:
    @user = users.find{|u| u.ability.cannot?(:read_notes, event)} || users.first
    mail bcc: to(users), subject: 'You are invited to an event'
  end

  include ActionView::Helpers::TextHelper # needed for pluralize()
  def remind(event, users = nil)
    @event = event
    users ||= @event.users
    @user = users.find{|u| u.ability.cannot?(:read_notes, event)} || users.first
    mail bcc: to(users), subject: "Reminder: #{event.display_name} is in #{pluralize event.hours_until, 'hour'}"
  end

  private

    def to(users)
      return users.map{|u| to(u)} unless users.is_a? User
      users.name.present? ? "#{users.name} <#{users.email}>" : users.email
    end

end
