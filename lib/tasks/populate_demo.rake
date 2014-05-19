namespace :db do

  task :populate_demo => :environment do

    def rand_coord(n)
      n + (rand/3) - (1/6)
    end
    center = [43.7, -79.4]

    # probability that a record would have a particular attribute
    event_attribute_probabilities = {name: 80, description: 30, notes: 10, address: 40, lat: 90}
    user_attribute_probabilities = {name: 90, description: 10, phone: 40, address: 60, lat: 90}
    def use_probabilities(record, attr_prob)
      attr_prob.each do |k, prob|
        record.send("#{k}=", nil) if (rand * 100) > prob
      end
      record.save
      record
    end

    # users
    # first user is automatically an admin, others are participants
    40.times do
      u = FactoryGirl.build :full_user, no_geocode: true, lat: rand_coord(center[0]), lng: rand_coord(center[1])
      u.skip_confirmation! # don't send emails
      use_probabilities(u, user_attribute_probabilities)
    end
    # handful of coordinators
    5.times do
      u = FactoryGirl.build :full_user, no_geocode: true, lat: rand_coord(center[0]), lng: rand_coord(center[1])
      u.skip_confirmation! # don't send emails
      u.roles.build name: :coordinator
      use_probabilities(u, user_attribute_probabilities)
    end

    # events and participants
    # past events
    30.times do
      e = FactoryGirl.build :full_past_event, no_geocode: true, lat: rand_coord(center[0]), lng: rand_coord(center[1])
      e.coordinator = User.coordinators.sample(1).first
      e = use_probabilities(e, event_attribute_probabilities)
      User.participants.sample(rand 3..7).each do |u|
        e.event_users.create user: u, status: EventUser.statuses[:attending]
      end
    end
    # future events
    20.times do
      e = FactoryGirl.build :full_event, no_geocode: true, lat: rand_coord(center[0]), lng: rand_coord(center[1])
      e.coordinator = User.coordinators.sample(1).first
      e = use_probabilities(e, event_attribute_probabilities)
      User.participants.sample(rand 7).each do |u|
        e.attend u
      end
    end

    # proposed events
    # with coordinator and date
    e = FactoryGirl.build :full_event, status: Event.statuses[:proposed], no_geocode: true, lat: rand_coord(center[0]), lng: rand_coord(center[1])
    e.coordinator = User.coordinators.sample(1).first
    e = use_probabilities(e, event_attribute_probabilities)
    e.save
    # with coordinator, no date
    e = FactoryGirl.build :full_event, status: Event.statuses[:proposed], start: nil, no_geocode: true, lat: rand_coord(center[0]), lng: rand_coord(center[1])
    e.coordinator = User.coordinators.sample(1).first
    e = use_probabilities(e, event_attribute_probabilities)
    e.save
    # with date, no coordinator
    e = FactoryGirl.build :full_event, status: Event.statuses[:proposed], no_geocode: true, lat: rand_coord(center[0]), lng: rand_coord(center[1])
    e = use_probabilities(e, event_attribute_probabilities)
    e.save

    # events with a date but no coordinator
    2.times do
      e = FactoryGirl.build :full_event, no_geocode: true, lat: rand_coord(center[0]), lng: rand_coord(center[1])
      e = use_probabilities(e, event_attribute_probabilities)
    end
    event_attribute_probabilities[:name] = 100
    # events with a coordinator but no date
    2.times do
      e = FactoryGirl.build :full_event, start: nil, no_geocode: true, lat: rand_coord(center[0]), lng: rand_coord(center[1])
      e.coordinator = User.coordinators.sample(1).first
      e = use_probabilities(e, event_attribute_probabilities)
    end
    # events with no date or coordinator
    2.times do
      e = FactoryGirl.build :full_event, start: nil, no_geocode: true, lat: rand_coord(center[0]), lng: rand_coord(center[1])
      e = use_probabilities(e, event_attribute_probabilities)
    end

  end
end