require 'spec_helper'

describe "Event Attendance" do

  include Warden::Test::Helpers
  before :each do
    @admin = create :admin
    @participant = create :participant
    Event.destroy_all
  end
  after :each do
    Warden.test_reset!
  end

  it "describes the coordinator as attending" do
    e = create :participatable_event
    login_as e.coordinator
    visit event_path e
    within '#rsvp' do
      expect(page).to have_content 'You are attending'
      expect(all('button').length).to eq 0
    end
    visit root_path
    within '#coordinating' do
      expect(page).to have_link e.display_name
    end
  end

  it "does not describes a coordinator as attending when they are not on this event" do
    e = create :participatable_event
    login_as create :coordinator
    visit event_path e
    within '#rsvp' do
      expect(page).to have_content 'You are not attending'
      expect(all('button').length).to eq 0
    end
  end

  it "joins an event" do
    e = create :participatable_event
    login_as @participant
    visit event_path e
    within '#rsvp' do
      expect(page).to have_content 'You are not attending'
      expect(all('button').length).to eq 1
      click_button 'Attend'
    end
    expect(current_path).to eq event_path e
    expect(page).to have_content 'You are attending'
    click_link 'Who'
    within '#participants' do
      expect(page).to have_link @participant.display_name
    end
    visit root_path
    within '#attending' do
      expect(page).to have_link e.display_name
    end
  end

  it "sends a confirmation email on joining an event" do
    e = create :participatable_event
    login_as @participant
    visit event_path e
    expect { click_button 'Attend' }.to change{ActionMailer::Base.deliveries.size}.by 1
    expect(last_email.bcc).to eq [@participant.email]
  end

  it "does not allow admins to attend events" do
    e = create :participatable_event
    login_as @admin
    visit event_path e
    expect(page).not_to have_button 'Attend'
  end

  it "does not allow coordinators to participate in events" do
    e = create :participatable_event
    login_as create :coordinator
    visit event_path e
    expect(page).not_to have_button 'Attend'
  end

  it "cancels attending an event" do
    e = create :participatable_event
    e.attend @participant
    login_as @participant
    visit event_path e
    within '#rsvp' do
      expect(page).to have_content 'You are attending'
      expect(all('button').length).to eq 1
      click_button 'Cancel'
    end
    expect(current_path).to eq event_path e
    expect(page).to have_content 'You are not attending'
    expect(page).not_to have_link @participant.email
    visit root_path
    expect(all('#attending').length).to eq 0
  end

  it "prevents joining a past event" do
    e = create :participatable_past_event
    login_as @participant
    visit event_path e
    expect(page).to have_content 'You did not attend'
    within '#rsvp' do
      expect(all('button').length).to eq 0
    end
  end

  it "prevents cancelling attendance on a past event" do
    e = create :participatable_event
    e.attend @participant
    e.update(start: 1.month.ago, duration: 1.hour)
    login_as @participant
    visit event_path e
    within '#rsvp' do
      expect(page).to have_content 'You attended'
      expect(all('button').length).to eq 0
    end
  end

  context "waitlist" do

    it "joins an event waitlist" do
      e = create :participatable_event, max: 1
      e.attend create :participant
      login_as @participant
      visit event_path e
      within '#rsvp' do
        expect(page).to have_content 'You are not attending'
        expect(all('button').length).to eq 1
        click_button 'Add To Waitlist'
      end
      expect(current_path).to eq event_path e
      expect(page).to have_content 'You are on the waitlist'
      within 'header' do
        click_link 'Events'
      end
      within '#may_be_attending' do
        expect(page).to have_link e.display_name
      end
    end

    it "removes oneself from a waitlist" do
      e = create :participatable_event, max: 1
      e.attend create :participant
      e.attend @participant
      login_as @participant
      visit event_path e
      within '#rsvp' do
        expect(page).to have_content 'You are on the waitlist'
        expect(all('button').length).to eq 1
        click_button 'Withdraw Request'
      end
      expect(current_path).to eq event_path e
      expect(page).to have_content 'You are not attending'
      click_link 'My Profile'
      visit root_path
      expect(all('#may_be_attending').length).to eq 0
    end

    it "adds users on a waitlist when a participant cancels" do
      e = create :participatable_event, max: 1
      will_cancel = create :participant
      e.attend will_cancel
      will_attend = create :participant
      e.attend will_attend # gets onto waitlist
      login_as will_cancel
      visit who_event_path e
      within '#participants' do
        expect(page).not_to have_link will_attend.display_name
      end
      click_link 'Event Details'
      within '#rsvp' do
        click_button 'Cancel'
      end
      click_link 'Who'
      within '#participants' do
        expect(page).to have_link will_attend.display_name
      end
      expect(last_email.bcc).to eq [will_attend.email]
      expect(last_email.subject).to match 'are attending'
    end

    it "removes participants when the max is decreased" do
      e = create :participatable_event, max: 2
      p1 = create :participant
      e.attend p1
      p2 = create :participant
      e.attend p2
      login_as @admin
      visit edit_event_path e
      fill_in 'Max', with: 1
      click_button 'Save & Notify'
      click_link 'Who'
      within '#participants' do
        expect(page).to have_link p1.display_name
        expect(page).not_to have_link p2.display_name
      end
      expect(last_email.subject).to match 'no longer attending'
      expect(last_email.bcc).to eq [p2.email]
    end

  end

  context "invitations" do

    it "allows coordinators to invite users to an event" do
      e = create :participatable_event, max: 1, lat: 50, lng: 50
      create :participant, lat: 50, lng: 51 # make sure there is someone who can be invited
      login_as e.coordinator
      visit event_path e
      click_link 'invite'
      within '#invite' do
        fill_in 'invite_near', with: 1
        fill_in 'invite_near_virgin', with: 0
        click_button 'Invite'
      end
      expect(page).to have_content '1 invitation will be sent'
      click_link 'Who'
      expect(page).to have_content '1 invitation is awaiting a response'
    end

    it "does not allow participants to invite users to an event" do
      e = create :participatable_event
      login_as @participant
      visit event_path e
      expect(all('#invite').length).to eq 0
    end

    # also tests that admins can invite users
    it "invites people to an event, one accepts and one declines" do
      2.times { create :participant, lat: 50, lng: 51 }
      e = create :participatable_event, lat: 50, lng: 51
      login_as @admin
      visit event_path e
      click_link 'invite'
      within '#invite' do
        fill_in 'invite_near', with: 0
        fill_in 'invite_near_virgin', with: 2
        click_button 'Invite'
      end
      expect(current_path).to eq event_path e
      expect(page).to have_content '2 invitations will be sent'
      logout
      login_as Invitation.first.user
      visit root_path
      within '#invited' do
        click_link e.display_name
      end
      within '#rsvp' do
        expect(page).to have_content 'been invited'
        click_button 'Attend'
      end
      expect(current_path).to eq event_path e
      within "#rsvp" do
        expect(page).to have_content 'are attending'
      end
      logout
      login_as Invitation.last.user
      visit event_path e
      within '#rsvp' do
        expect(page).to have_content 'been invited'
        click_button 'Will Not Attend'
      end
      expect(current_path).to eq event_path e
      within "#rsvp" do
        expect(page).to have_content 'are not attending'
      end
      logout
      login_as @admin
      visit who_event_path e
      expect(page).to have_content '1 invitation was declined'
    end

    it "shows invite form when there are spots available or when requested" do
      e = create :participatable_event, lat: 50, lng: 50
      potential_attendee = create :participant, lat: 51, lng: 51
      e.attend @participant
      login_as e.coordinator
      visit who_event_path e
      expect(page).to have_button 'Invite'
      e.update max: 1
      visit who_event_path e
      expect(page).not_to have_button 'Invite'
      click_link 'Invite'
      expect(page).to have_button 'Invite'
    end

  end

  context "taking attendance" do

    it "allows coordinator to take attendance" do
      e = create :participatable_past_event
      eu = e.event_users.create user: @participant, status: :attending
      p2 = create :participant
      eu2 = e.event_users.create user: p2, status: :attending
      login_as e.coordinator
      visit event_path e
      click_link 'take attendance'
      expect(page).not_to have_link 'Edit Attendance'
      expect(page).to have_link @participant.display_name
      expect(page).to have_link p2.display_name
      check("attendance_#{eu.id}")
      uncheck("attendance_#{eu2.id}")
      click_button 'Take Attendance'
      expect(current_path).to eq who_event_path e
      expect(page).to have_content 'Attendance taken'
      within '#participants' do
        expect(page).to have_link @participant.display_name
        expect(page).not_to have_link p2.display_name
      end
      within '#absent_participants' do
        expect(page).not_to have_link @participant.display_name
        expect(page).to have_link p2.display_name
      end      
    end

    it "does not allow taking attendance on a cancelled event" do
      e = create :participatable_past_event, status: :cancelled
      e.event_users.create user: @participant, status: :attending
      login_as e.coordinator
      visit who_event_path e
      expect(page).not_to have_button 'Take Attendance'
    end

    it "does not allow taking attendance when an event isn't over" do
      e = create :participatable_event, status: :cancelled
      e.attend @participant
      login_as e.coordinator
      visit who_event_path e
      expect(page).not_to have_button 'Take Attendance'
    end

    it "does not allow admins to take attendance" do
      e = create :participatable_past_event
      e.event_users.create user: @participant, status: :attending
      login_as @admin
      visit who_event_path e
      expect(page).not_to have_button 'Take Attendance'
    end

    it "does not allow participants to take attendance" do
      e = create :participatable_past_event
      e.event_users.create user: @participant, status: :attending
      login_as @participant
      visit who_event_path e
      expect(page).not_to have_button 'Take Attendance'
    end

    it "allows coordinator to edit attendance to make corrections" do
      e = create :participatable_past_event
      eu = e.event_users.create user: @participant, status: :attended
      p2 = create :participant
      eu2 = e.event_users.create user: p2, status: :no_show
      login_as e.coordinator
      visit event_path e
      click_link 'Who'
      within '#participants' do
        expect(page).to have_link @participant.display_name
        expect(page).not_to have_link p2.display_name
      end
      expect(page).not_to have_button 'Take Attendance'
      click_link 'Edit Attendance'
      expect(current_path).to eq who_event_path e
      uncheck("attendance_#{eu.id}")
      check("attendance_#{eu2.id}")
      click_button 'Take Attendance'
      expect(current_path).to eq who_event_path e
      expect(page).to have_content 'Attendance taken'
      within '#participants' do
        expect(page).not_to have_link @participant.display_name
        expect(page).to have_link p2.display_name
      end
    end

  end

end