require 'spec_helper'

describe User do

  context "attributes" do

    context "validity" do

      it "has a valid factory" do
        expect(create(:user)).to be_valid
      end

      it "is invalid without an email" do
        expect(build(:user, email: nil)).not_to be_valid
      end

      it "is invalid without a password" do
        expect(build(:user, password: nil)).not_to be_valid
      end

      it "is invalid with an overly short password" do
        expect(build(:user, password: "foo")).not_to be_valid
      end

      it "is invalid with an incorrect password confirmation" do
        expect(build(:user, password: "1234567", password_confirmation: "1234568")).not_to be_valid
      end

      it "does not allow multiple users with the same email, case insensitively" do
        user1 = build :user
        user1.email = user1.email.upcase
        user1.save
        expect(build(:user, email: user1.email.downcase)).not_to be_valid
      end

      it "is valid with a latitude in range" do
        expect(build :event, lat: 40, lng: -80).to be_valid
      end

      it "is invalid with a latitude out of range" do
        expect(build :event, lat: 3000, lng: -80).not_to be_valid
      end

    end

    context "geocoding" do

      it "geocodes an address" do
        e = build :user, address: '1600 Pennsylvania Avenue, Washington, DC'
        e.valid? # triggers geocoding
        expect(e.lat).to be_within(1).of(38)
        expect(e.lng).to be_within(1).of(-77)
      end

      it "does not override given coordinates" do
        e = build :user, address: '1600 Pennsylvania Avenue, Washington, DC', lat: 40, lng: -75
        e.valid? # triggers geocoding
        expect(e.lat).to eq 40
        expect(e.lng).to eq -75
      end

    end

    context "name" do

      it "has a non-blank display name" do
        expect(build(:user).display_name).not_to be_blank
      end

      it "generates a name based on email" do
        u = create :user, name: nil, email: 'joe.smith@example.com'
        expect(u.name).to eq 'Joe Smith'
      end

      it "does not generate a name when one is given" do
        expect(create(:user, name: 'My Name', email: 'joe.smith@example.com').name).to eq 'My Name'
      end

    end

    it "has an avatar which is a url" do
      expect(build(:user).avatar).to match URI::regexp(%w(http https))
    end

    # all fields should be stripped, this just tests two (excessive to check them all)
    context "normalizing attributes" do

      it "strips the name" do
        expect(create(:user, name: "  Joe\n").name).to eq 'Joe'
      end

      it "nullifies empty description" do
        expect(create(:user, description: " \n").description).to be_nil
      end

    end

  end

  context "roles" do

    it "ensures the first user is an admin but others are participants" do
      User.delete_all # todo: figure out why this is needed... should be handled by database cleaner
      expect(create(:user).roles.where(name: Role.names[:admin]).count).to eq 1
      expect(create(:user).roles.where(name: Role.names[:participant]).count).to eq 1
    end

    it "creates a user with the specified role" do
      role_name = :coordinator
      expect(create(:user, roles_attributes: [name: role_name]).roles.where(name: Role.names[role_name]).count).to eq 1
    end

    it "responds properly to has_role?" do
      p = create :participant
      expect(p.has_role? :participant).to be_true
      expect(p.has_role? :coordinator).to be_false
      expect(p.has_role? :admin).to be_false
      p.roles.create name: :coordinator
      expect(p.has_role? :participant).to be_true
      expect(p.has_role? :coordinator).to be_true
      expect(p.has_role? :admin).to be_false
    end

    it "response properly to has_any_role?" do
      p = create :participant
      expect(p.has_any_role? :participant).to be_true
      expect(p.has_any_role? :coordinator).to be_false
      expect(p.has_any_role? :participant, :coordinator).to be_true
      expect(p.has_any_role? :participant, :coordinator, :admin).to be_true
      expect(p.has_any_role? :coordinator, :admin).to be_false
      expect(p.has_any_role? :admin).to be_false
      p.roles.create name: :coordinator
      expect(p.has_any_role? :participant).to be_true
      expect(p.has_any_role? :coordinator).to be_true
      expect(p.has_any_role? :participant, :coordinator).to be_true
      expect(p.has_any_role? :participant, :coordinator, :admin).to be_true
      expect(p.has_any_role? :coordinator, :admin).to be_true
      expect(p.has_any_role? :admin).to be_false
    end

  end

  context "multiple users" do

    before :each do
      User.delete_all # todo: figure out why this is needed... should be handled by database cleaner
    end

    it "orders users by name" do
      b = create :user, name: 'b'
      a = create :user, name: 'a'
      c = create :user, name: 'c'
      expect(User.by_name).to eq [a, b, c]
    end

    it "lists users that have coordinates" do
      w_coords = create :user, lat: 50, lng: 50
      wo_coords = create :user, lat: nil, lng: nil
      expect(User.geocoded).to eq [w_coords]
    end

    it "lists users according to role" do
      a = create :admin
      c = create :coordinator
      p1 = create :participant
      p1.roles.create name: :coordinator
      p2 = create :participant
      p3 = create :participant
      bad_user = create :participant
      bad_user.roles.destroy_all
      participants = User.participants
      expect(participants.length).to eq 3
      expect(participants).to include p1
      expect(participants).to include p2
      expect(participants).to include p3
      coordinators = User.coordinators
      expect(coordinators.length).to eq 2
      expect(coordinators).to include c
      expect(coordinators).to include p1
      admins = User.admins
      expect(admins.length).to eq 1
      expect(admins.first).to eq a
      nobodies = User.roleless
      expect(nobodies).to eq [bad_user]
    end

    it "searches for users" do
      u1 = create :user, name: 'Joe Smith', email: 'joe_smith@example.com'
      u2 = create :user, name: 'Sally', email: 'sally_smith@example.com'
      u3 = create :user, name: 'Bob Dole', email: 'blabla@example.com'
      smiths = User.search 'smith' # checks that it looks in name and email fields
      expect(smiths.length).to eq 2
      expect(smiths).to include u1
      expect(smiths).to include u2
      bobs = User.search 'bob' # checks for case sensitivity
      expect(bobs.length).to eq 1
      expect(bobs).to include u3
      expect(User.search('Jack').length).to eq 0
    end

    it "lists users who have not attended and are not attending any events" do
      c = create :coordinator
      p_virgin = create :participant
      p_cancelled = create :participant
      cancelled = create :participatable_event, coordinator: c, status: :cancelled
      cancelled.event_users.create user: p_cancelled, status: :attending
      p_attending = create :participant
      future = create :participatable_event, coordinator: c
      future.attend p_attending
      p_attended = create :participant
      past = create :participatable_event, coordinator: c, start: 1.month.ago
      past.event_users.create user: p, status: :attended
      virgins = User.participated_in_no_events
      expect(virgins).to include p_virgin
      expect(virgins).to include p_cancelled
      expect(virgins).not_to include p_attending
      expect(virgins).to include p_attended
    end

    it "lists coordinators not taking attendance" do
      p = create :participant
      # c_takes always take attendance
      c_takes = create :coordinator
      # not using :participatable_past_event because we want to ensure they're at least 3 days old, i.e. threshold for when attendance should be taken by
      e1 = create :participatable_event, start: 1.month.ago, coordinator: c_takes
      e1.event_users.create user: p, status: :attended
      # c_verybad never takes attendance
      c_verybad = create :coordinator
      e2 = create :participatable_event, start: 1.month.ago, coordinator: c_verybad
      e2.event_users.create user: p, status: :attending
      e3 = create :participatable_event, start: 1.month.ago, coordinator: c_verybad
      e3.event_users.create user: p, status: :attending
      # c_bad sometimes takes attendance
      c_bad = create :coordinator
      e4 = create :participatable_event, start: 1.month.ago, coordinator: c_bad
      e4.event_users.create user: p, status: :attended
      e5 = create :participatable_event, start: 1.month.ago, coordinator: c_bad
      e5.event_users.create user: p, status: :attending
      # expect the two bad coordinators to be listed, ordered by worst coordinator first
      bad_coordinators = User.coordinators_not_taking_attendance
      expect(bad_coordinators.index c_verybad).to be < bad_coordinators.index(c_bad)
    end

    it "lists users not involved in an event, ordered by distance to it" do
      e = create :participatable_event, lat: 50, lng: 50
      p_attending = create :participant, lat: 51, lng: 51
      e.attend p_attending
      p_invited = create :participant, lat: 51, lng: 51
      e.event_users.create user: p_invited, status: :invited
      p_nogeocode = create :participant
      p_near = create :participant, lat: 51, lng: 51
      p_far = create :participant, lat: 60, lng: 60
      expect(User.not_involved_in_by_distance(e)).to eq [p_near, p_far]
    end

    it "returns nobody when looking for users near non-geocoded event" do
      e = create :event
      expect(User.not_involved_in_by_distance(e)).to eq []
    end

  end

  context "events" do

    it "lists events a user is coordinating" do
      u = create :coordinator
      create :event, coordinator: u
      create :event, coordinator: u
      create :event # event 3, not coordinating
      expect(u.coordinating_events.length).to eq 2
    end

    it "lists events a user is participating in" do
      p = create :participant
      c = create :coordinator
      e_not_participating = create :participatable_event, coordinator: c
      e_participating = create :participatable_event, coordinator: c
      e_participating.attend p
      e_cancelled = create :participatable_event, coordinator: c
      e_cancelled.attend p
      e_cancelled.update status: :cancelled
      expect(p.participating_events).to eq [e_participating]
    end

    it "lists events a user is involved with" do
      # user is a coordinator and participant
      u = create :coordinator
      u.roles.create name: :participant
      c = create :coordinator
      # 1 - is coordinator
      e_coordinating = create :participatable_event, coordinator: u
      # 2 - is a participant
      e_participating = create :participatable_event, coordinator: c
      e_participating.attend u
      # 3 - is a participant
      e_participating_past = create :participatable_event, coordinator: c
      e_participating_past.attend u
      e_participating_past.update(start: 1.month.ago, duration: 1.hour)
      # not counted - attending a cancelled event
      e_cancelled = create :participatable_event, coordinator: c
      e_cancelled.attend u
      e_cancelled.update(status: Event.statuses[:cancelled])
      # not counted - on the waitlist for an event
      e_waitlisted = create :participatable_event, max: 1, coordinator: c
      e_waitlisted.attend create :participant
      e_waitlisted.attend u
      # not counted - not participating in this event
      e_not_attending = create :participatable_event, coordinator: c
      expect(u.events.length).to eq 3
      expect(u.events).to include e_coordinating
      expect(u.events).to include e_participating
      expect(u.events).to include e_participating_past
    end

    it "lists events a user might be attending" do
      # todo: also test for event_user status :requested
      p1 = create :participant
      p2 = create :participant
      c = create :coordinator
      e_attending = create :participatable_event, max: 1, coordinator: c
      e_attending.attend p1
      e_attending.attend p2 # p2 waitlisted
      e_waitlisted = create :participatable_event, max: 1, coordinator: c
      e_waitlisted.attend p2
      e_waitlisted.attend p1
      e_waitlisted_past = create :participatable_event, max: 1, coordinator: c
      e_waitlisted_past.attend p2
      e_waitlisted_past.attend p1
      e_waitlisted_past.update(start: 1.month.ago, duration: 1.hour)
      e_cancelled = create :participatable_event, max: 1, coordinator: c
      e_cancelled.attend p2
      e_cancelled.attend p1
      e_cancelled.update(status: Event.statuses[:cancelled])
      expect(p1.potential_events).to eq [e_waitlisted]
    end

    it "lists upcoming events the user has been invited to" do
      p1 = create :participant
      p2 = create :participant
      c = create :coordinator
      e_attending = create :participatable_event, coordinator: c
      e_attending.attend p1
      e_invited = create :participatable_event, coordinator: c
      e_invited.event_users.create user: p1, status: :invited
      e_cancelled = create :participatable_event, coordinator: c
      e_cancelled.event_users.create user: p1, status: :invited
      e_cancelled.update status: :cancelled
      e_p2_invited = create :participatable_event, coordinator: c
      e_p2_invited.event_users.create user: p2, status: :invited
      expect(p1.open_invites).to eq [e_invited]
    end

  end

end