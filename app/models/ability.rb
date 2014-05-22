class Ability
  include CanCan::Ability

  def initialize(user)

    user ||= User.new

    if user.persisted?

      can :read, Event, can_have_participants?: true
      can :who, Event do |event|
        can? :read, event
      end
      can :calendar, Event
      can :index, :geocode

      can [:show, :me], User
      can [:read_contact, :read_attendance, :read_address, :update], User, id: user.id
      can :destroy, Role, user_id: user.id
      can :deactivate, User do |u|
        u.roles.reject{|r| can? :destroy, r }.empty?
      end

      if user.has_role? :admin
        can :manage, [Event, Role, :setting]
        cannot :take_attendance, Event
        can [:index, :map, :ask_to_import, :import, :read_contact, :read_attendance], User
      end

      if user.has_role? :coordinator
        can :read, Event
        can [:update, :read_notes], Event do |event|
          !event.coordinator || (event.coordinator == user)
        end
        can [:ask_to_cancel, :cancel, :invite, :take_attendance], Event, coordinator_id: user.id
        can :read_attendance, User
      end

      if user.has_role? :participant
        can [:attend, :unattend], Event
      end

    end

  end

end