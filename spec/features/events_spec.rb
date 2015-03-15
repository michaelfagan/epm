require 'spec_helper'

describe "Events" do

  include Warden::Test::Helpers
  before :each do
    @admin = create :admin
    @participant = create :participant
  end
  after :each do
    Warden.test_reset!
  end

  describe "CRU" do

    context "creating" do

      it "cancels creating an event" do
        login_as @admin
        visit root_path
        click_link 'Add New Event'
        click_button 'Cancel'
        expect(current_path).to eq root_path
      end

      it "creates a dateless event" do
        login_as @admin
        visit root_path
        click_link 'Add New Event'
        e = build :full_event
        fill_in 'Name', with: e.name
        click_button 'Save'
        expect(current_path).to eq event_path Event.last
        expect(page).to have_content e.name
        expect(page).to have_content 'No date set'
      end

      it "creates an event with dates when js is disabled" do
        e = build :event
        login_as @admin
        visit new_event_path
        fill_in 'Date', with: e.start.to_date
        select (e.duration / 3600), from: 'For'
        click_button 'Save'
        expect(current_path).to eq event_path Event.last
        # expect(page).to have_content Event.humanize(e.start) # todo: figure out timezone issues causing this to fail
        expect(page).to have_content "#{e.duration_hours} hour"
        expect(page).not_to have_content 'No date set'
      end

      it "creates an event with dates when js is enabled", js: true do
        login_as @admin
        visit new_event_path
        e = build :event
        find('.ui-datepicker-trigger').click;
        within '.ui-datepicker' do
          click_link 28 # select date towards the end of the current month
        end
        select (e.duration / 3600), from: 'For'
        click_button 'Save'
        expect(current_path).to eq event_path Event.last
        # expect(page).to have_content Event.humanize(e.start) # todo: figure out timezone issues causing this to fail
        expect(page).to have_content "#{e.duration_hours} hour"
        expect(page).not_to have_content 'No date set'
      end

      it "prevents participants from creating events" do
        login_as @participant
        visit root_path
        expect(page).not_to have_content 'Add New Event'
        visit new_event_path
        expect(page).to have_content 'Sorry'
      end

      it "prevents coordinators from creating events" do
        login_as create :coordinator
        visit root_path
        expect(page).not_to have_content 'Add New Event'
        visit new_event_path
        expect(page).to have_content 'Sorry'
      end

    end

    context "show" do

      it "views an event" do
        login_as @admin
        e = create :event
        visit root_path
        click_link e.display_name
        expect(current_path).to eq event_path e
        expect(page).to have_content e.display_name
      end

      it "shows a map when geocoded", js: true do
        e = create :full_event
        login_as @admin
        visit event_path e
        expect(map_points).to eq 2 # self and geocoded location
      end

      it "shows no map when not geocoded", js: true do
        e = create :event
        login_as @admin
        visit event_path e
        expect(all('.map').length).to eq 0
      end

    end

    context "updating" do

      it "cancels updating an event" do
        e = create :event
        login_as @admin
        visit event_path e
        click_link 'Edit'
        fill_in 'Name', with: 'new name'
        click_button 'Cancel'
        expect(current_path).to eq event_path e
        expect(page).not_to have_content 'new name'
      end

      # consider separating out testing that the duration select is showing the right value
      it "updates an event" do
        e = create :full_event
        login_as @admin
        visit event_path e
        click_link 'Edit'
        expect(find('#event_duration option[selected]').text).to have_content e.duration_hours
        new_event_name = 'new event name'
        fill_in 'Name', with: new_event_name
        click_button 'Save'
        expect(current_path).to eq event_path(e)
        expect(page).to have_content 'saved'
        expect(page).to have_content new_event_name
      end

      context "time input" do

        it "disallows an invalid time" do
          e = create :full_event
          login_as @admin
          visit edit_event_path e
          fill_in 'Time', with: 'foo'
          click_button 'Save'
          expect(page).to have_content 'must be in the format'
        end

        it "allows a valid time" do
          e = create :full_event
          login_as @admin
          visit edit_event_path e
          fill_in 'Time', with: '10:15'
          click_button 'Save'
          expect(current_path).to eq event_path e
          expect(page).not_to have_content 'must be in the format'
        end

      end

      it "prevents updating an event without permission" do
        login_as @participant
        e = create :participatable_event
        visit event_path e
        expect(page).not_to have_content 'Edit'
        visit edit_event_path e
        expect(page).to have_content 'Sorry'
      end

      context "email notifications" do

        before :each do
          @coordinator = create :coordinator
          @participant = create :participant
          @e = create :participatable_event, coordinator: @coordinator
          @e.attend @participant
        end

        it "separately emails coordinator and participants upon significantly changing an event" do
          login_as @admin
          visit edit_event_path @e
          fill_in 'Name', with: 'New name'
          # separately emails those with and without ability to view event notes
          expect{ click_button 'Save & Notify' }.to change{ActionMailer::Base.deliveries.size}.by 2
          # this is a bit fragile as it relies on knowing/caring the order of emails sent. todo: unfragilize
          expect(ActionMailer::Base.deliveries[-2].bcc).to eq [@coordinator.email]
          expect(last_email.bcc).to eq [@participant.email]
        end

        it "emails coordinator but not participants upon changing event notes" do
          login_as @admin
          visit edit_event_path @e
          fill_in 'Notes', with: 'new note'
          expect{ click_button 'Save & Notify' }.to change{ActionMailer::Base.deliveries.size}.by 1
          expect(last_email.bcc).to eq [@coordinator.email]
        end

        it "emails participants but not coordinator upon the coordinator significantly changing an event" do
          login_as @coordinator
          visit edit_event_path @e
          fill_in 'Name', with: 'New name'
          expect{ click_button 'Save & Notify' }.to change{ActionMailer::Base.deliveries.size}.by 1
          expect(last_email.bcc).to eq [@participant.email]
        end

        it "emails attendees but not coordinator upon significantly changing an event and also assigning a coordinator" do
          new_coordinator = create :coordinator
          login_as @admin
          visit edit_event_path @e
          fill_in 'Name', with: 'New name'
          choose "event_coordinator_id_#{new_coordinator.id}"
          ActionMailer::Base.deliveries.clear
          # expecting to send a notice to the new coordinator of the event
          # and also the notice to existing participants of changes
          # which should be the last email
          expect{ click_button 'Save & Notify' }.to change{ActionMailer::Base.deliveries.size}.by 2
          expect(last_email.bcc).to eq [@participant.email]
        end

        it "does not email attendees upon changing an event in a minor way" do
          login_as @admin
          visit edit_event_path @e
          choose 'event_coordinator_id' # select the nil option
          expect{ click_button 'Save & Notify' }.to change{ActionMailer::Base.deliveries.size}.by 0
        end

        it "does not email attendees upon significantly changing an event when opting out" do
          login_as @admin
          visit edit_event_path @e
          fill_in 'Name', with: 'some new name'
          expect{ click_button 'Save Without Notifications' }.to change{ActionMailer::Base.deliveries.size}.by 0
        end

        it "does not email attendees of changes to past events" do
          e = create :participatable_past_event
          e.attend @participant
          login_as @admin
          visit edit_event_path e
          fill_in 'Name', with: 'some new name'
          expect{ click_button 'Save & Notify' }.to change{ActionMailer::Base.deliveries.size}.by 0
        end

      end

    end

    context "coordinator" do

      before :each do
        @coordinator = create :coordinator
      end

      it "prevents coordinators from cancelling an event with no coordinator" do
        login_as @coordinator
        visit event_path(create :event)
        expect(page).not_to have_content 'Cancel'
      end

      it "prevents coordinators from cancelling an event with another coordinator" do
        login_as @coordinator
        e = create :event, coordinator:(create :coordinator)
        visit event_path(e)
        expect(page).not_to have_content 'Cancel'
      end

      it "allows a coordinator to cancel their own event" do
        e = create :event, coordinator: @coordinator
        login_as @coordinator
        visit event_path e
        click_link 'Cancel'
        fill_in 'Reason', with: 'Bad weather'
        click_button 'Cancel Event'
        expect(current_path).to eq event_path e
        expect(page).to have_content 'Event cancelled'
        expect(e.reload.cancelled?).to be_true
      end

      it "allows admin to set a coordinator" do
        login_as @admin
        visit new_event_path
        fill_in 'Name', with: 'some event'
        choose "event_coordinator_id_#{@coordinator.id}"
        click_button 'Save'
        click_link 'Who'
        expect(page).to have_content @coordinator.display_name
      end

      describe "email notifications" do

        it "notifies a coordinator when a new event is assigned to them" do
          login_as @admin
          visit new_event_path
          fill_in 'Name', with: 'some event'
          choose "event_coordinator_id_#{@coordinator.id}"
          expect{ click_button 'Save' }.to change{ActionMailer::Base.deliveries.size}.by 1
          expect(last_email.to.first).to match @coordinator.email
        end

        it "notifies a coordinator when an existing event is assigned to them" do
          e = create :event, coordinator: nil
          login_as @admin
          visit edit_event_path e
          choose "event_coordinator_id_#{@coordinator.id}"
          expect{ click_button 'Save' }.to change{ActionMailer::Base.deliveries.size}.by 1
          expect(last_email.to.first).to match @coordinator.email
        end

        it "does not notify a coordinator when they assign an event to themselves" do
          e = create :event, coordinator: nil
          login_as @coordinator
          visit edit_event_path(e)
          choose "event_coordinator_id_#{@coordinator.id}"
          expect{ click_button 'Save' }.to change{ActionMailer::Base.deliveries.size}.by 0
        end

        it "does not notify a coordinator when they are assigned a past event" do
          e = create :past_event, coordinator: nil
          login_as @admin
          visit edit_event_path e
          choose "event_coordinator_id_#{@coordinator.id}"
          expect{ click_button 'Save' }.to change{ActionMailer::Base.deliveries.size}.by 0
        end

      end

      it "allows coordinator to set an event's coordinator only to his/herself" do
        coordinator2 = create :coordinator
        login_as @admin
        visit new_event_path
        fill_in 'Name', with: 'event with no coordinator'
        click_button 'Save'
        logout
        login_as @coordinator
        visit root_path
        click_link 'event with no coordinator'
        click_link 'Edit'
        expect(all('#coordinator input').length).to eq 2 # nil and self
      end

      it "allows a coordinator to edit a coordinatorless event" do
        e = create :event, name: 'event with no coordinator'
        login_as @coordinator
        visit root_path
        click_link 'event with no coordinator'
        click_link 'Edit'
        name = 'some name'
        fill_in 'Name', with: name
        click_button 'Save'
        expect(current_path).to eq event_path e
        expect(page).to have_content name
      end

      it "allows a coordinator to edit an event they are coordinating" do
        e = build :event
        e.coordinator = @coordinator
        e.save
        login_as @coordinator
        visit edit_event_path e
        name = 'some name'
        fill_in 'Name', with: name
        click_button 'Save'
        expect(current_path).to eq event_path e
        expect(page).to have_content name
      end

      it "allows coordinator to edit a dateless event" do
        e = create :event, coordinator: @coordinator, start: nil, name: 'foo'
        login_as @coordinator
        visit root_path
        click_link 'foo'
        click_link 'Edit'
        name = 'some name'
        fill_in 'Name', with: name
        click_button 'Save'
        expect(current_path).to eq event_path e
        expect(page).to have_content name
      end

      it "does not allow a coordinator to edit an event with another coordinator" do
        e = build :event
        e.coordinator = @coordinator
        e.save
        login_as create :coordinator
        visit event_path e
        expect(page).not_to have_content 'Edit'
        visit edit_event_path(e)
        expect(current_path).not_to eq edit_event_path(e)
        expect(page).to have_content 'Sorry'
      end

      it "includes a user as an event's coordinator when they are no longer a coordinator" do
        e = create :participatable_past_event
        e.coordinator.roles.where(name: Role.names[:coordinator]).destroy_all
        login_as @admin
        visit edit_event_path e
        expect(page).to have_link e.coordinator.display_name
      end

    end

    context "geocoding" do

      it "geocodes with ajax", js: true do
        # checks that geocoding happens and that a map shows up
        login_as @admin
        visit new_event_path
        fill_in 'Address', with: '1600 Pennsylvania Avenue, Washington, DC'
        within '#address' do
          expect(page).to have_content 'Enter an address'
        end
        expect(map_points).to eq 1 # self only
        find_field('Address').trigger('blur')
        Timeout.timeout(5) do
          loop until page.evaluate_script('jQuery.active').zero?
        end
        expect(find_field('Latitude', visible: false).value.to_i).to be_within(1).of(38)
        expect(find_field('Longitude', visible: false).value.to_i).to be_within(1).of(-77)
        expect(map_points).to eq 2 # should show self and geocoded location
        within '#address' do
          expect(page).to have_content 'Drag marker to adjust'
        end
      end

      it "geocodes without javascript" do
        e = create :event
        login_as @admin
        visit edit_event_path e
        fill_in 'Address', with: '1600 Pennsylvania Avenue, Washington, DC'
        click_button 'Save'
        expect(e.reload.lat).to be_within(1).of(38)
        expect(e.lng).to be_within(1).of(-77)
      end

    end

  end

  context "listing events" do

    it "exports to icalendar" do
      login_as @admin
      visit events_path(format: 'ics')
      expect(response_headers['Content-Type'].start_with? 'text/calendar').to be_true
      # todo: figure out how to get the following to work
      # cals = Icalendar.parse(source)
      # expect(cals.length).to eq 1
      # expect(cals.first.events.length).to eq Event.with_date.length
    end

    context "approval" do

      it "shows events awaiting approval to admins" do
        e = create :participatable_event, status: :proposed
        login_as @admin
        visit root_path
        within '#awaiting_approval' do
          expect(page).to have_link e.display_name
        end
      end

      it "does not show events awaiting approval to coordinators" do
        e = create :participatable_event, status: :proposed
        login_as create :coordinator
        visit root_path
        expect(page).not_to have_link e.display_name
      end

      # no test needed for participants, as this is tested below in
      #   "does not show non-participatable events to participants"

    end

    it "shows past events on the home page to admins" do
      e = create :participatable_past_event
      login_as @admin
      visit root_path
      within '#past' do
        expect(page).to have_link e.display_name
      end
    end

    context "needing participants" do

      it "shows events needing participants to admins" do
        create :participatable_event, min: 1, name: 'needs one person'
        login_as @admin
        visit root_path
        within '#needing_more_participants' do
          expect(page).to have_link 'needs one person'
        end
      end

      it "shows events needing participants to participants if they are not attending" do
        create :participatable_event, min: 1, name: 'needs one person'
        e = create :participatable_event, min: 2, name: 'needs two people'
        e.attend @participant
        login_as @participant
        visit root_path
        within '#needing_more_participants' do
          expect(page).to have_link 'needs one person'
          expect(page).not_to have_content 'needs two people'
        end
      end

      it "does not show events needing participants to coordinators" do
        create :participatable_event, min: 1
        login_as create :coordinator
        visit root_path
        expect(all('#needing_more_participants').length).to eq 0
      end

    end

    context "accepting participants" do

      it "shows events accepting participants to admins" do
        create :participatable_event, name: 'foo'
        login_as @admin
        visit root_path
        within '#accepting_more_participants' do
          expect(page).to have_link 'foo'
        end
      end

      it "shows events accepting participants to participants if they are not attending" do
        create :participatable_event, name: 'foo'
        e = create :participatable_event, name: 'bar'
        e.attend @participant
        login_as @participant
        visit root_path
        within '#accepting_more_participants' do
          expect(page).to have_link 'foo'
          expect(page).not_to have_link 'bar'
        end
      end

      it "does not show events accepting participants to coordinators" do
        create :participatable_event
        login_as create :coordinator
        visit root_path
        expect(all('#accepting_more_participants').length).to eq 0
      end

    end

    context "events page maps" do

      it "shows one map for each section with a geocoded event", js: true do
        c = create :coordinator
        # three sections, two of whom have maps
        e_needing = create :participatable_event, coordinator: c, lat: 50, lng: 50, min: 1
        e_accepting = create :participatable_event, coordinator: c
        e_full = create :participatable_event, lat: 50, lng: 50, coordinator: c, max: 1
        e_full.attend create :participant
        login_as @admin
        visit root_path
        within '#needing_more_participants' do
          expect(all('.map').length).to eq 1
        end
        within '#accepting_more_participants' do
          expect(all('.map').length).to eq 0
        end
        within '#full' do
          expect(all('.map').length).to eq 1
        end
      end

      it "shows the right number of things on a map", js: true do
        create :event, lat: 30, lng: 30
        create :event, lat: 20, lng: 20
        create :event
        login_as @admin
        visit root_path
        expect(map_points).to eq 3 # self and 2 geocoded events
      end

    end

    it "shows a no-events message when there are no events" do
      Event.destroy_all # todo: why is this not handled by database cleaner?
      login_as @admin
      visit root_path
      expect(page).to have_content 'no events'
    end

    it "does not show non-participatable events to participants" do
      e = create :event, coordinator: nil, name: 'bla'
      login_as @participant
      visit root_path
      expect(page).not_to have_link 'bla'
    end

    it "shows next upcoming events on home page" do
      current = create :participatable_event
      login_as @admin
      visit root_path
      within '#accepting_more_participants' do
        expect(page).to have_link current.display_name
      end
    end

    it "displays events for a particular month" do
      e_this = create :event, start: Time.zone.now
      e_prev = create :event, start: e_this.start.advance(months: -1)
      e_next = create :event, start: e_this.start.advance(months: 1)
      login_as @admin
      visit root_path
      click_link 'Monthly Calendar'
      expect(current_path).to eq calendar_events_path
      expect(page).to have_link e_this.display_name
      expect(page).not_to have_link e_prev.display_name
      expect(page).not_to have_link e_next.display_name
      click_link 'previous'
      expect(page).not_to have_link e_this.display_name
      expect(page).to have_link e_prev.display_name
      expect(page).not_to have_link e_next.display_name
      click_link 'next'
      click_link 'next'
      expect(page).not_to have_link e_this.display_name
      expect(page).not_to have_link e_prev.display_name
      expect(page).to have_link e_next.display_name
    end

    it "displays a map on the calendar page", js: true do
      create :full_event, start: Time.zone.now
      login_as @admin
      visit calendar_events_path
      expect(map_points).to eq 2 # self and event
    end

    it "displays events needing attendance to coordinators" do
      c = create :coordinator
      e = create :participatable_past_event, coordinator: c
      e.event_users.create user: create(:participant), status: :attending
      login_as c
      visit root_path
      within '#needing_attendance_taken' do
        expect(page).to have_link e.display_name
      end
    end

    it "displays coordinators who need to take attendance, not the events themselves to admin" do
      c = create :coordinator
      e = create :participatable_event, coordinator: c, start: 1.week.ago # older than the 3 day threshold
      e.event_users.create user: create(:participant), status: :attending
      login_as @admin
      visit root_path
      expect(all('#needing_attendance_taken').length).to eq 0
      within '#coordinators_not_taking_attendance' do
        expect(page).to have_link c.display_name
      end
    end

  end

  context "status" do

    context "approval" do

      it "admin approves an event on creation" do
        login_as @admin
        visit new_event_path
        fill_in 'Name', with: 'some event'
        choose 'Approved'
        click_button 'Save'
        expect(page).not_to have_link 'Approve'
      end

      it "admin approves an event" do
        login_as @admin
        # create a new event that is proposed
        visit new_event_path
        fill_in 'Name', with: 'some event'
        choose 'Proposed'
        click_button 'Save'
        # approve it
        click_link 'Approve'
        expect(page).to have_content  'approved'
        expect(page).not_to have_link 'Approve'
      end

      it "sends an email to the coordinator on approving an event" do
        coordinator = create :coordinator
        e = create :event, coordinator: coordinator, status: :proposed
        login_as @admin
        visit event_path e
        expect{click_link 'Approve'}.to change{ActionMailer::Base.deliveries.size}.by 1
        expect(last_email.to).to eq [coordinator.email]
      end

      it "prevents a coordinator from approving an event" do
        c = create :coordinator
        e = create :event, status: :proposed, coordinator: c
        login_as c
        visit event_path e
        expect(page).not_to have_link 'Approve'
        click_link 'Edit'
        expect(current_path).to eq edit_event_path e
        expect(page).not_to have_content 'Status'
      end

      it "emails admins when an event is ready for approval" do
        e = create :event, status: :proposed # missing a coordinator
        c = create :coordinator
        login_as c
        visit edit_event_path e
        choose "event_coordinator_id_#{c.id}"
        expect{ click_button 'Save' }.to change{ActionMailer::Base.deliveries.size}.by 1
        expect(last_email.bcc).to eq User.admins.map{|u| u.email}
      end

      it "does not email admins when an event is ready for approval by their own change" do
        User.admins.where.not(id: @admin.id).destroy_all # there should only be one admin. todo: figure out why this isn't handled by database cleaner
        e = create :event, status: :proposed, coordinator: create(:coordinator), start: nil, name: 'foo'
        login_as @admin
        visit edit_event_path e
        fill_in 'Date', with: Time.zone.tomorrow.to_date
        # it will send an email to tell the coordinator about the change in time
        # but should not be sending an email to the admin
        expect{ click_button 'Save & Notify' }.to change{ActionMailer::Base.deliveries.size}.by 1
        expect(last_email.bcc).not_to include @admin.email
      end

    end

    context "deleting" do

      it "allows admin to delete an event" do
        e = create :event
        login_as @admin
        visit event_path e
        click_link 'Delete'
        expect(current_path).to eq cancel_event_path e
        click_button 'Delete Event'
        expect(current_path).to eq events_path
        expect(page).to have_content "#{e.display_name} deleted"
        expect(page).not_to have_link e.display_name
      end

      it "does not allow coordinators to delete an event" do
        # even if it's an event they are coordinating
        e = create :event, coordinator: create(:coordinator)
        login_as e.coordinator
        visit event_path e
        click_link 'Delete'
        expect(page).to have_button 'Cancel Event'
        expect(page).not_to have_button 'Delete Event'
      end

      it "does not allow participants to delete an event" do
        e = create :participatable_event
        login_as @participant
        visit event_path e
        expect(page).not_to have_link 'Cancel'
        visit cancel_event_path e
        expect(current_path).not_to eq cancel_event_path e
        expect(page).to have_content 'Sorry'
      end

    end

    context "cancelling" do

      it "cancels an event" do
        login_as @admin
        e = create :event
        visit event_path e
        click_link 'Cancel'
        click_button 'Cancel Event'
        expect(current_path).to eq event_path e
        expect(page).to have_content 'Event cancelled'
        expect(page).not_to have_link 'Cancel'
        expect(e.reload.cancelled?).to be_true
      end

      it "prevents participants from cancelling an event" do
        login_as @participant
        e = create :event
        visit event_path e
        expect(page).not_to have_content 'Cancel'
      end

      it "send emails to admins+coordinator and participants when an event is cancelled" do
        other_admin = create :admin
        admins = User.admins
        e = create :participatable_event
        participant = create :participant
        e.attend participant
        login_as @admin
        visit event_path e
        click_link 'Cancel'
        expect{ click_button 'Cancel Event' }.to change{ActionMailer::Base.deliveries.size}.by 2 # email to admins/coordinators and to participants
      end

      it "send emails to admins and participants but not the coordinator when an event is cancelled by the coordinator" do
        coordinator = create :coordinator
        e = create :participatable_event, coordinator: coordinator
        participant = create :participant
        e.attend participant
        login_as coordinator
        visit event_path e
        click_link 'Cancel'
        expect{ click_button 'Cancel Event' }.to change{ActionMailer::Base.deliveries.size}.by 2 # email to admins/coordinators and to participants
        # todo: fix fragility; this relies on order of emails sent
        expect(ActionMailer::Base.deliveries[-2].bcc.length).to eq User.admins.length
      end

      it "does not send email when an event is cancelled by the only admin, that does not have a coordinator or participants" do
        User.admins.where.not(id: @admin.id).destroy_all # make sure there is only the one admin. todo: figure out why not handled by database cleaner
        e = create :event
        login_as @admin
        visit event_path e
        expect{ click_link 'Cancel' }.to change{ActionMailer::Base.deliveries.size}.by 0
      end

    end

  end

  context "admin and coordinator features" do

    it "shows events with missing info to admins" do
      c = create :coordinator
      no_coordinator = create :full_event, coordinator: nil
      no_date = create :full_event, coordinator: c, start: nil
      no_location = create :full_event, coordinator: c, lat: nil, no_geocode: true
      okay = create :full_event, coordinator: c
      login_as @admin
      visit root_path
      within '#needing_a_coordinator' do
        expect(page).to have_link no_coordinator.display_name
      end
      within '#missing_a_date_or_location' do
        expect(page).not_to have_link no_coordinator.display_name
        expect(page).to have_link no_date.display_name
        expect(page).to have_link no_location.display_name
        expect(page).not_to have_link okay.display_name
      end
    end

    context "notes" do

      # the first test creates the note through the ui to test that, the others don't need to

      it "shows notes to admins" do
        login_as @admin
        visit new_event_path
        fill_in 'Name', with: 'Event name'
        fill_in 'Notes', with: 'Some note'
        click_button 'Save'
        expect(page).to have_content 'Some note'
      end

      it "shows notes to coordinator of an event" do
        e = create :participatable_event, notes: 'Some note'
        login_as e.coordinator
        visit event_path e
        expect(page).to have_content 'Some note'
      end

      it "shows notes to coordinator for a coordinatorless event" do
        e = create :event, coordinator: nil, notes: 'Some note'
        login_as create :coordinator
        visit event_path e
        expect(page).to have_content 'Some note'
      end

      it "does not show notes to coordinator on another coordinator's event" do
        e = create :event, coordinator: create(:coordinator), notes: 'Some note'
        login_as create :coordinator
        visit event_path e
        expect(page).not_to have_content 'Some note'
      end

      it "does not show notes to participant" do
        e = create :participatable_event, notes: 'Some note'
        e.attend create(:participant)
        login_as e.participants.first
        visit event_path e
        expect(page).not_to have_content 'Some note'
      end

    end

    context "csv" do

      it "does not allow participants to export" do
        login_as create :participant
        visit root_path
        expect(page).not_to have_link 'Export Events'
      end

      it "does not allow coordinators to export" do
        login_as create :coordinator
        visit root_path
        expect(page).not_to have_link 'Export Events'
      end

      it "exports" do
        login_as create :admin
        visit root_path
        click_link 'Export Events'
        csv = CSV.parse(source) # using source as page has normalized the whitespace (thus having no newlines)
        expect(csv.length).to eq (Event.count + 1)
        ['id', 'name', 'description', 'notes', 'address', 'status', 'min participants', 'max participants', 'created', 'updated', 'start', 'finish', 'coordinator', 'participants invited', 'participants attending', 'participants cancelled', 'participants waitlisted', 'participants no_show'].each do |field|
          expect(csv.first).to include field
        end
      end

    end

  end

end