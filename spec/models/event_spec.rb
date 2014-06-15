require 'spec_helper'

describe Event do

  context "attributes with permissions" do

    context "display name" do

      it "has a display name with some text" do
        expect(build(:event).display_name).not_to be_blank
      end

      it "has a display name using the description when no name is given" do
        expect(build(:event, name: nil, description: 'foo').display_name).to eq 'foo'
      end

      it "has a display name using the address when no name or description is given" do
        e = build :event, name: nil, description: nil, address: '123 fake street', no_geocode: true
        expect(e.display_name).to eq '123 fake street'
      end

    end

  end

  context "significant attributes" do

    it "is significantly changed when changing the start time" do
      e = create :event
      e.track
      e.update start: e.start - 1.hour
      expect(e.changed_significantly?).to be_true
    end

    it "is not significantly changed when changing the coordinator" do
      e = create :event
      e.track
      e.update coordinator_id: create(:coordinator).id
      expect(e.changed_significantly?).to be_false
    end

  end

  context "validity and normalization" do

    it "is invalid without a name, description, start, or address/coords" do
      empty_hash = { start: nil, name: nil, description: nil, address: nil, lat: nil, lng: nil }
      expect(build :event, empty_hash).not_to be_valid
      expect(build :event, empty_hash.merge(start: Time.zone.now)).to be_valid
      expect(build :event, empty_hash.merge(name: 'some name')).to be_valid
      expect(build :event, empty_hash.merge(description: 'some description')).to be_valid
      expect(build :event, empty_hash.merge(address: '123 fake street', no_geocode: true)).to be_valid
      expect(build :event, empty_hash.merge(lat: 40, lng: -80)).to be_valid
      expect(build :event, empty_hash.merge(lat: 40)).not_to be_valid
    end

    it "is invalid with a zero duration" do
      expect(build :event, duration: 0).not_to be_valid
    end

    it "is invalid without a finish later than the start" do
      event = build :event
      event.finish = event.start - 1.day
      expect(event).not_to be_valid
    end

    it "invalid with a start and no finish" do
      expect(build :event, start: Time.zone.now, finish: nil).not_to be_valid
    end

    it "is invalid with a maximum below the minimum" do
      expect(build :event, min: 10, max: 5).not_to be_valid
    end

    it "is valid with a latitude in range" do
      expect(build :event, lat: 40, lng: -80).to be_valid
    end

    it "is invalid with a latitude out of range" do
      expect(build :event, lat: 3000, lng: -80).not_to be_valid
    end

    # all fields should be stripped, this just tests two (excessive to check them all)
    context "normalizing attributes" do

      it "strips the name" do
        expect(create(:event, name: "  Stuff\n").name).to eq 'Stuff'
      end

      it "nullifies empty description" do
        expect(create(:event, description: "\r\n ").description).to be_nil
      end

    end

  end

  context "geocoding" do

    it "geocodes an address" do
      e = build :event, address: '1600 Pennsylvania Avenue, Washington, DC'
      e.valid? # triggers geocoding
      expect(e.lat).to be_within(1).of(38)
      expect(e.lng).to be_within(1).of(-77)
    end

    it "geocodes an address with newlines" do
      e = build :event, address: "1600 Pennsylvania Avenue\nWashington, DC"
      e.valid? # triggers geocoding
      expect(e.lat).to be_within(1).of(38)
      expect(e.lng).to be_within(1).of(-77)
    end

    it "does not override given coordinates" do
      e = build :event, address: '1600 Pennsylvania Avenue, Washington, DC', lat: 40, lng: -75
      e.valid? # triggers geocoding
      expect(e.lat).to eq 40
      expect(e.lng).to eq -75
    end

  end

  context "time methods" do

    it "responds properly to past? method" do
      expect(build(:event).past?).to be_false
      expect(build(:past_event).past?).to be_true
      expect(build(:event, start: nil).past?).to be_nil
    end

    it "sets finish when given a duration" do
      now = Time.zone.now
      expect(build(:event, start: now, duration: 1.hour).finish).to eq (now + 1.hour)
      expect(build(:event, start: now, duration: 8.hours).finish).to eq (now + 8.hours)
    end

    it "properly calculates duration" do
      expect(build(:event, start: Time.zone.now, duration: nil, finish: Time.zone.now + 1.hour).duration).to eq 1.hour.to_i
      expect(build(:event, start: Time.zone.now, duration: nil, finish: Time.zone.now + 8.hours).duration).to eq 8.hours.to_i
    end

    it "properly calculates time until" do
      expect(build(:event, start: nil).time_until).to be_nil
      expect(build(:event, start: 1.month.from_now).time_until).to be_within(1.day).of(1.month)
      expect(build(:event, start: 2.weeks.ago).time_until).to be_within(1.minute).of(- 2.weeks)
    end

    it "properly calculates hours until" do
      expect(build(:event, start: nil).hours_until).to be_nil
      expect(build(:event, start: 1.hour.from_now).hours_until).to eq 1
      expect(build(:event, start: 1.day.from_now).hours_until).to eq 24
    end

  end

  context "cancelling" do

    it "cancels an event" do
      e = create :event
      e.cancel
      expect(e.cancelled?).to be_true
    end

    it "cancels an event with reasons" do
      e = create :event
      e.cancel(cancel_notes: 'reason for admin', cancel_description: 'public reason')
      expect(e.notes).to include 'reason for admin'
      expect(e.description).to include 'public reason'
    end

    it "deletes invites when an event is cancelled" do
      e = create :event
      Invitation.create event: e, user: create(:user)
      expect(Invitation.where(event_id: e.id).any?).to be_true
      e.cancel
      expect(Invitation.where(event_id: e.id).reload.any?).to be_false
    end

  end

  it "responds properly to awaiting_approval? method" do
    c = create :coordinator
    expect(create(:event, status: :proposed, coordinator: c).awaiting_approval?).to be_true
    expect(create(:event, status: :approved, coordinator: c).awaiting_approval?).to be_false
    expect(create(:past_event, status: :proposed, coordinator: c).awaiting_approval?).to be_false
    expect(create(:event, status: :proposed, coordinator: nil).awaiting_approval?).to be_false
    expect(create(:event, status: :proposed, coordinator: c, start: nil, name: 'foo').awaiting_approval?).to be_false
  end

  context "users" do

    context "participatable_by?" do

      it "can join an event if there is nothing preventing it" do
        u = create :participant
        e = create :participatable_event
        expect(e.participatable_by? u).to be_true
      end

      it "cannot be joined if in the past" do
        u = create :participant
        e = create :participatable_past_event
        expect(e.participatable_by? u).to be_false
      end

      it "cannot be joined by non-participants" do
        u = create :coordinator
        e = create :participatable_event
        expect(e.participatable_by? u).to be_false
      end

      it "cannot be joined by someone who is already coordinating it" do
        u = create :coordinator
        u.roles.create name: :participant
        e = create :event, coordinator: u
        expect(e.participatable_by? u).to be_false
      end

      it "cannot be joined if there is no coordinator" do
        u = create :participant
        e = create :participatable_event, coordinator: nil
        expect(e.participatable_by? u).to be_false
      end

      it "cannot be joined if it has no dates" do
        u = create :participant
        e = create :participatable_event, start: nil, name: 'foo'
        expect(e.participatable_by? u).to be_false
      end

      it "cannot be joined if it has been cancelled" do
        u = create :participant
        e = create :participatable_event, status: :cancelled
        expect(e.participatable_by? u).to be_false
      end

      # todo: test that not participatable when a user has been denied for the event
      # denied feature not yet implemented

    end

    it "adds a participant" do
      e = create :participatable_event
      p = create :participant
      e.attend p
      expect(e.event_users.count).to eq 1
      eu = e.event_users.first
      expect(eu.user).to eq p
      expect(eu.status).to eq 'attending'
    end

    it "adds a participant to the waitlist" do
      e = create :participatable_event, max: 1
      e.attend create :participant
      p = create :participant
      eu = e.attend p
      expect(e.event_users.length).to eq 2
      expect(eu.status).to eq 'waitlisted'
    end

    it "cancels participation" do
      e = create :participatable_event
      p = create :participant
      eu = e.attend p
      e.unattend p
      expect(e.event_users.count).to eq 1
      expect(eu.reload.status).to eq 'cancelled'
    end

    it "withdraws from waitlist" do
      e = create :participatable_event, max: 1
      e.attend create :participant
      p = create :participant
      e.attend p
      e.unattend p
      expect(e.event_users.count).to eq 2
      eu = e.event_users.last
      expect(eu.user).to eq p
      expect(eu.status).to eq 'withdrawn'
    end

    context "invitations" do

      context "suggested number" do

        it "suggests number of invitations for a participtable event" do
          expect(build(:participatable_event, lat: 50, lng: 50).suggested_invitations).to be > 0
        end

        it "suggests zero invitations for a non-participtable event" do
          expect(build(:participatable_event, lat: 50, lng: 50, status: :proposed).suggested_invitations).to eq 0
          expect(build(:participatable_event, lat: 50, lng: 50, start: 1.month.ago).suggested_invitations).to eq 0
        end

        it "suggests zero invitations for events without coordinates" do
          expect(build(:participatable_event).suggested_invitations).to eq 0
        end

        it "suggests zero invitations for full events" do
          e = create :participatable_event, lat: 50, lng: 50, max: 1
          e.attend create :participant
          expect(e.suggested_invitations).to eq 0
        end

        it "suggests at least as many invitations as there are remaining spots" do
          e = create :participatable_event, lat: 50, lng: 50, max: 5
          expect(e.suggested_invitations).to be >= 5
        end

        it "suggests at least as many invitations as participants are needed" do
          e = create :participatable_event, lat: 50, lng: 50, min: 3
          expect(e.suggested_invitations).to be >= 3
        end

        # this should be okay however due to rounding, may not. so commented out for now
        # it "suggests fewer invitations when some have already been sent out" do
        #   e = create :participatable_event, lat: 50, lng: 50, max: 20
        #   suggested = e.suggested_invitations
        #   5.times { e.event_users.create user: create(:participant), status: :invited }
        #   expect(e.suggested_invitations).to be < suggested
        # end

      end

      it "invites one person" do
        e = create :participatable_event
        p = create :participant
        invited = e.invite p
        expect(invited).to eq 1
        eus = e.event_users.to_a
        expect(eus.length).to eq 1
        expect(eus.first.user).to eq p
        expect(eus.first.status).to eq 'invited'
        invitations = Invitation.where(event_id: e.id).to_a
        expect(invitations.length).to eq 1
        expect(invitations.first.user).to eq p
      end

      it "invites multiple people" do
        e = create :participatable_event
        expect(e.invite [create(:participant), create(:participant)]).to eq 2
      end

      it "does not doubly invite duplicates" do
        e = create :participatable_event
        p = create :participant
        p_dup = User.where(id: p.id).first
        expect(e.invite [p, p_dup]).to eq 1
      end

      it "does not invite those already involved" do
        e = create :participatable_event
        attending = create :participant
        e.attend attending
        already_invited = create :participant
        e.event_users.create user: already_invited, status: :invited
        cancelled = create :participant
        e.event_users.create user: cancelled, status: :cancelled
        uninvolved = create :participant
        expect(e.invite [attending, uninvolved, cancelled, already_invited]).to eq 1
        invitation = Invitation.last
        expect(invitation.user).to eq uninvolved
        expect(invitation.event).to eq e
      end

    end

    context "number of participants/spots" do

      it "returns the number of participants needed when there is no min" do
        e = create :participatable_event, min: 0
        expect(e.participants_needed).to eq 0
        expect(e.below_min).to be_false
        expect(e.reached_max).to be_false
      end

      it "returns the number of participants needed when there is a min" do
        e = create :participatable_event, min: 1
        expect(e.participants_needed).to eq 1
        expect(e.below_min).to be_true
        expect(e.reached_max).to be_false
        e.attend create :participant
        expect(e.reload.participants_needed).to eq 0
        expect(e.reload.below_min).to be_false
        expect(e.reached_max).to be_false
      end

      it "returns the number of remaining spots when there is no max" do
        e = create :participatable_event, max: nil
        expect(e.remaining_spots).to be_true
        expect(e.below_min).to be_false
        expect(e.reached_max).to be_false
      end

      it "returns the number of remaining spots when there is a max" do
        e = create :participatable_event, max: 1
        expect(e.remaining_spots).to eq 1
        expect(e.below_min).to be_false
        expect(e.reached_max).to be_false
        e.attend create :participant
        expect(e.remaining_spots).to eq 0
        expect(e.reload.below_min).to be_false
        expect(e.reached_max).to be_true
      end

      it "returns whether an event is full when there is no max" do
        e = create :participatable_event, max: nil
        expect(e.full?).to be_false
        expect(e.below_min).to be_false
        expect(e.reached_max).to be_false
        e.attend create :participant
        expect(e.full?).to be_false
        expect(e.reload.below_min).to be_false
        expect(e.reached_max).to be_false
      end

      it "returns whether an event is full when there is a max" do
        e = create :participatable_event, max: 1
        expect(e.full?).to be_false
        expect(e.below_min).to be_false
        expect(e.reached_max).to be_false
        e.attend create :participant
        expect(e.full?).to be_true
        expect(e.reload.below_min).to be_false
        expect(e.reached_max).to be_true
      end

    end

    context "list" do

      it "has an list of participants" do
        e = create :participatable_event
        expect(e.participants.length).to eq 0
        participant = create :participant
        e.attend participant
        expect(e.participants.reload).to eq [participant]
      end

      it "has a list of waitlisted users" do
        e = create :participatable_event, max: 1
        e.attend create :participant
        expect(e.waitlisted.count).to eq 0
        participant = create :participant
        e.attend participant
        expect(e.waitlisted).to eq [participant]
      end

      it "lists coordinator as user when there are no participants" do
        coordinator = create :coordinator
        e = create :participatable_event, coordinator: coordinator
        expect(e.users).to eq [coordinator]
      end

      it "lists coordinator and participants as users" do
        e = create :participatable_event, coordinator: create(:coordinator)
        participant = create :participant
        e.attend participant
        expect(e.users.length).to eq 2
        expect(e.users).to include participant
      end

    end

    context "waitlist" do

      it "adds participants from the waitlist, in the correct order" do
        # create an event with one person who will cancel, and a waitlist of three people
        #   one 'newbie' who hasn't been to any events and two others
        other_event = create :participatable_event
        p1 = create :participant
        other_event.attend p1
        p2 = create :participant
        other_event.attend p2
        newbie = create :participant
        e = create :participatable_event, max: 1
        will_cancel = create :participant
        e.attend will_cancel
        # on the waitlist:
        e.attend p1
        e.attend p2
        e.attend newbie
        expect(e.participants.reload).to eq [will_cancel]
        # first person cancells, should bump up newbie
        e.unattend will_cancel
        expect(e.participants.reload).to eq [newbie]
        expect(last_email.subject).to match 'are attending'
        expect(last_email.bcc).to eq [newbie.email]
        # further cancellations
        e.waitlisted.reload
        e.unattend newbie
        expect(e.participants.reload).to eq [p1]
        e.waitlisted.reload
        e.unattend p1
        expect(e.participants.reload).to eq [p2]
      end

      it "does not add participants from the waitlist for cancelled events" do
        e = create :participatable_event
        participant = create :participant
        # artificially place someone on the waiting list even though they could just be attending
        e.event_users.create user: participant, status: EventUser.statuses[:waitlisted]
        e.status = :cancelled
        e.add_from_waitlist
        expect(e.participants.reload.length).to eq 0
      end

      it "does not add participants from the waitlist for past events" do
        e = create :participatable_event
        participant = create :participant
        # artificially place someone on the waiting list even though they could just be attending
        e.event_users.create user: participant, status: EventUser.statuses[:waitlisted]
        e.start = 1.month.ago
        e.finish = 1.week.ago
        e.add_from_waitlist
        expect(e.participants.reload.length).to eq 0
      end

      it "adds participants from the waitlist when increasing the max" do
        e = create :participatable_event, max: 1
        p1 = create :participant
        e.attend p1
        p2 = create :participant
        e.attend p2
        expect(e.participants.reload).to eq [p1]
        e.update max: 100
        expect(e.participants.reload.length).to eq 2
      end

      it "adds participants from the waitlist when eliminiating the max" do
        e = create :participatable_event, max: 1
        p1 = create :participant
        e.attend p1
        p2 = create :participant
        e.attend p2
        expect(e.participants.reload).to eq [p1]
        e.update max: nil
        expect(e.participants.reload.length).to eq 2
      end

      it "removes participants to the waitlist when adding a max" do
        e = create :participatable_event
        p1 = create :participant
        e.attend p1
        p2 = create :participant
        e.attend p2
        expect(e.participants.reload.length).to eq 2
        e.update max: 1
        expect(e.participants.reload).to eq [p1]
        expect(e.waitlisted).to eq [p2]
      end

      it "removes participants to the waitlist when decreasing the max" do
        e = create :participatable_event, max: 2
        p1 = create :participant
        e.attend p1
        p2 = create :participant
        e.attend p2
        expect(e.participants.reload.length).to eq 2
        e.update max: 1
        expect(e.participants.reload).to eq [p1]
        expect(e.waitlisted).to eq [p2]
      end

      it "does not change the participants when not changing the max" do
        e = create :participatable_event, max: 1, name: 'foo'
        p1 = create :participant
        e.attend p1
        e.attend create :participant
        e.update name: 'bar'
        expect(e.participants.reload).to eq [p1]
      end

      it "does not change the participants when changing the max for a cancelled event" do
        e = create :participatable_event, max: 1, name: 'foo'
        p1 = create :participant
        e.attend p1
        e.attend create :participant
        e.update status: :cancelled
        e.update max: :nil
        expect(e.participants.reload).to eq [p1]
      end

    end

    context "taking attendance" do

      it "takes attendance when everyone showed up" do
        e = create :participatable_event
        eu1 = e.attend create :participant
        eu2 = e.attend create :participant
        e.take_attendance [eu1.id, eu2.id]
        expect(eu1.reload.attended?).to be_true
        expect(eu2.reload.attended?).to be_true
      end

      it "takes attendance when some people showed up" do
        e = create :participatable_event
        eu1 = e.attend create :participant
        eu2 = e.attend create :participant
        e.take_attendance [eu1.id]
        expect(eu1.reload.attended?).to be_true
        expect(eu2.reload.no_show?).to be_true
      end

      it "takes attendance when nobody showed up" do
        e = create :participatable_event
        eu1 = e.attend create :participant
        eu2 = e.attend create :participant
        e.take_attendance []
        expect(eu1.reload.no_show?).to be_true
        expect(eu2.reload.no_show?).to be_true
      end

      it "does not affect attendance when given eu ids which don't apply" do
        e = create :participatable_event, max: 2
        eu1 = e.attend create :participant
        eu2 = e.attend create :participant
        eu3 = e.attend create :participant # on the waitlist
        e2 = create :participatable_event, coordinator: e.coordinator
        eu4 = e2.attend eu1.user # on a different event
        e.take_attendance [eu1.id, eu2.id, eu3.id, eu4.id, 98732] # also passing in an id which doesn't exist
        expect(eu1.reload.attended?).to be_true
        expect(eu2.reload.attended?).to be_true
        expect(eu3.reload.waitlisted?).to be_true
        expect(eu4.reload.attending?).to be_true
      end

      it "lists events needing attendance taken" do
        Event.destroy_all # todo: why is this not handled by database cleaner
        c = create :coordinator
        p = create :participant
        not_past = create :participatable_event, coordinator: c
        not_past.attend p
        nobody_went = create :participatable_past_event, coordinator: c
        cancelled = create :participatable_past_event, coordinator: c, status: :cancelled
        cancelled.event_users.create user: p, status: :attending
        needs = create :participatable_past_event, coordinator: c
        needs.event_users.create user: p, status: :attending
        already_taken = create :participatable_past_event, coordinator: c
        already_taken.event_users.create user: p, status: :attended
        expect(Event.needing_attendance_taken).to include needs
        expect(Event.needing_attendance_taken).not_to include not_past
        expect(Event.needing_attendance_taken).not_to include nobody_went
        expect(Event.needing_attendance_taken).not_to include cancelled
        expect(Event.needing_attendance_taken).not_to include already_taken
      end

    end

  end

  context "multiple events" do

    before :each do
      # todo: figure out why database cleaner isn't handling this
      Event.destroy_all
    end

    it "orders by soonest first" do
      event1 = create :event
      event2 = create :past_event
      event3 = create :event, start: event1.start + 1.hour
      events = Event.all
      expect(events.first).to eq event2
      expect(events.last).to eq event3
    end

    it "lists past events only, ordered by most recent first" do
      event1 = create :event
      event2 = create :past_event
      event3 = create :past_event, start: event2.start - 1.hour, finish: event2.finish - 1.hour # farther in the past than event2
      expect(Event.past).to eq [event2, event3]
    end

    it "lists only events which are not over" do
      event1 = create :event
      event2 = create :past_event
      event3 = create :event, start: event1.start + 1.hour
      events = Event.not_past
      expect(events.length).to eq 2
      expect(events).not_to include event2
    end

    it "lists only events a user can participate in" do
      # ie testing scope participatable_by_user
      #  which tests participatability of the user for the event, not the event itself
      c = create :coordinator
      participant = create :participant
      not_involved = create :participatable_event, coordinator: c
      attending = create :participatable_event, coordinator: c
      attending.attend participant
      waitlisted = create :participatable_event, max: 1, coordinator: c
      waitlisted.attend create :participant
      waitlisted.attend participant
      invited = create :participatable_event, coordinator: c
      invited.event_users.create user: participant, status: :invited
      cancelled = create :participatable_event, coordinator: c
      cancelled.attend participant
      cancelled.unattend participant
      events = Event.participatable_by participant
      expect(events.length).to eq 3
      expect(events).to include not_involved
      expect(events).to include invited
      expect(events).to include cancelled
    end

    it "lists events needing participants" do
      c = create :coordinator
      p = create :participant
      no_min = create :participatable_event, coordinator: c
      no_min_attending = create :participatable_event, coordinator: c
      no_min_attending.attend p
      meets_min = create :participatable_event, max: 1, coordinator: c
      meets_min.attend p
      needs = create :participatable_event, min: 1, coordinator: c
      needs_cancelled = create :participatable_event, min: 1, coordinator: c
      needs_cancelled.update status: :cancelled
      needs_past = create :participatable_past_event, min: 1, coordinator: c
      expect(Event.needing_participants).to eq [needs]
    end

    it "lists events which do not need but can take more participants" do
      c = create :coordinator
      p = create :participant
      has_spots = create :participatable_event, coordinator: c
      has_spots_with_max = create :participatable_event, max: 2, coordinator: c
      has_spots_with_max.attend p
      no_spots = create :participatable_event, max: 1, coordinator: c
      no_spots.attend p
      needs = create :participatable_event, min: 1, coordinator: c
      has_spots_cancelled = create :participatable_event, coordinator: c
      has_spots_cancelled.update status: :cancelled
      has_spots_past = create :participatable_past_event
      events = Event.accepting_not_needing_participants
      expect(events.length).to eq 2
      expect(events).to include has_spots
      expect(events).to include has_spots_with_max
    end

    it "lists events without a coordinator" do
      c = create :coordinator
      create :event, coordinator: c
      event2 = create :event, coordinator: nil
      events = Event.coordinatorless
      expect(events.length).to eq 1
      expect(events.first).to eq event2
    end

    it "lists events without dates" do
      create :event
      e = create :event, start: nil, name: 'foo'
      events = Event.dateless
      expect(events.length).to eq 1
      expect(events.first).to eq e
    end

    it "list events that can have participants" do
      e = create :participatable_event
      create :event, coordinator: nil
      events = Event.participatable
      expect(events.length).to eq 1
      expect(events.first).to eq e
    end

    it "lists events within a given month" do
      create :event, start: '2013-10-01'
      nov1 = create :event, start: '2013-11-01'
      nov2 = create :event, start: '2013-11-02'
      dec = create :event, start: '2013-12-01'
      jan = create :event, start: '2014-01-01'
      create :event, start: '2014-02-01'
      events_n = Event.in_month(2013, 11)
      events_d = Event.in_month(2013, 12)
      events_j = Event.in_month(2014, 1)
      expect(events_n.length).to eq 2
      expect(events_n).to include nov1
      expect(events_n).to include nov2
      expect(events_d).to eq [dec]
      expect(events_j).to eq [jan]
    end

    it "lists events awaiting approval" do
      c = create :coordinator
      e1 = create :event, status: :proposed, coordinator: c
      e2 = create :event, status: :proposed, coordinator: c
      e_approved = create :event, status: :approved, coordinator: c
      e_past = create :past_event, status: :proposed, coordinator: c
      e_no_coordinator = create :event, status: :proposed, coordinator: nil
      e_no_date = create :event, status: :proposed, coordinator: c, start: nil, name: 'foo'
      events = Event.awaiting_approval
      expect(events.length).to eq 2
      expect(events).to include e1
      expect(events).to include e2
    end

    it "lists events which will begin in two days" do # used for sending reminders
      c = create :coordinator
      now = Time.zone.now
      early  = create :participatable_event, start: now , coordinator: c
      late = create :participatable_event, start: now + 5.days, coordinator: c
      in_day = create :participatable_event, start: now + 2.days, coordinator: c
      in_day_proposed = create :participatable_event, start: now + 2.days, status: :proposed, coordinator: c
      expect(Event.will_happen_in_two_days).to eq [in_day]
    end

  end

end