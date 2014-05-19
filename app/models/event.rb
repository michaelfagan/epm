class Event < ActiveRecord::Base

  strip_attributes

  def coordinator_id=(val)
    # this was needed due to radio button converting 'nil' value to 'on' to 0
    val = nil unless val.to_i > 0
    super val
  end

  def changed_significantly?
    # todo: remove lat+lng from this and test separataly via removal or addition of coords or distance change > n
    ['start', 'finish', 'name', 'description', 'address', 'lat', 'lng'].each do |attr|
      return true if self.send(attr) != prior[attr]
    end
    false
  end

  attr_accessor :prior
  def track
    self.prior = attributes
    ['past?', 'awaiting_approval?'].each do |meth|
      self.prior[meth] = send(meth)
    end
  end

  enum status: [:proposed, :approved, :cancelled]

  validate :must_not_be_empty
  def must_not_be_empty
    if start.blank? && name.blank? && description.blank? && address.blank? && !coords
      errors.add(:base, 'An event must have a name, description, date, or address')
    end
  end

  validate :must_start_before_finish
  validates :finish, presence: true, if: "start.present?"
  def must_start_before_finish
    if start.present? && finish.present? && start > finish
      errors.add(:finish, 'must be after the start')
    end
  end

  before_validation do |event|
    event.finish = nil if event.start.blank?
    # don't allow saving with only one of lat, lng; must be neither or both
    event.lat = nil if event.lng.blank?
    event.lng = nil if event.lat.blank?
  end

  def min=(val)
    val = 0 if val.blank?
    super(val)
  end
  validate :max_must_be_at_least_min
  def max_must_be_at_least_min
    if max.present? && max < min
      errors.add(:max, 'must be greater than the minimum, or blank')
    end
  end

  # allow for adding a reason for cancelling an event, with separate fields for admin/coordinator and participants
  attr_accessor :cancel_notes, :cancel_description
  def cancel_notes=(str)
    str = str.strip unless str.nil?
    if str.present?
      self.notes = "Cancelled because: #{str}\n\n#{notes}".strip
      @cancel_notes = str
    end
  end
  def cancel_description=(str)
    str = str.strip unless str.nil?
    if str.present?
      self.description = "Cancelled because: #{str}\n\n#{description}".strip
      @cancel_description = str
    end
  end

  has_many :event_users, dependent: :destroy
  has_many :participants, -> { where 'event_users.status' => EventUser.statuses_array(:attending, :attended) }, through: :event_users, source: :user
  has_many :waitlisted, -> { where('event_users.status' => EventUser.statuses[:waitlisted]).order('event_users.updated_at') }, through: :event_users, source: :user
  belongs_to :coordinator, class_name: 'User'
  def users # i.e. participants and the coordinator
    people = participants.to_a
    people << coordinator if coordinator
    people
  end

  # this section identical to that in model user.rb
  acts_as_mappable
  attr_accessor :no_geocode # force geocoding to not happen. used for testing
  after_validation :geocode, if: "!no_geocode && address_changed? && address.present? && (lat.blank? || lng.blank?)"
  validates :lat, numericality: {greater_than_or_equal_to: -90, less_than_or_equal_to: 90}, allow_nil: true
  validates :lng, numericality: {greater_than_or_equal_to: -180, less_than_or_equal_to: 180}, allow_nil: true

  default_scope { order :start }
  scope :with_date, -> { where 'start IS NOT NULL AND finish IS NOT NULL' }
  scope :past, -> { where('finish < ?', Time.zone.now).reorder('finish DESC') }
  scope :not_past, -> { where 'start IS NULL OR finish > ?', Time.zone.now }
  scope :participatable_by, ->(user) { # checks user for participatablility, assumed already checking that the events for participatability
    where.not("id IN (SELECT event_id FROM event_users WHERE user_id = ? AND status IN (?))", user.id, EventUser.statuses_array(:attending, :waitlisted, :requested, :denied))
      .where.not(coordinator_id: user.id)
      .distinct
  }
  scope :coordinatorless, -> { where coordinator: nil }
  scope :dateless, -> { where start: nil }
  scope :participatable, -> { where.not(start: nil).where.not(coordinator_id: nil).where('events.status = ?', statuses[:approved]) }
  scope :not_cancelled, -> { where 'events.status != ?', statuses[:cancelled] }
  scope :awaiting_approval, -> { not_past.where 'events.status = ? AND coordinator_id IS NOT NULL AND start IS NOT NULL', statuses[:proposed] }
  scope :needing_participants, -> { participatable.not_past.where(below_min: true) }
  scope :accepting_not_needing_participants, -> { participatable.not_past.where(below_min: false, reached_max: false) }
  scope :needing_attendance_taken, -> { participatable.past.joins("INNER JOIN event_users ON event_users.event_id = events.id AND event_users.status = #{EventUser.statuses[:attending]}").distinct }
  scope :in_month, ->(year, month) { # can pass in integers or strings which are integers
    month ||= ''
    year ||= ''
    unless (1..12).include?(month.to_i) && year.to_s.length == 4
      month = Time.zone.now.month
      year = Time.zone.now.year
    end
    start = Time.zone.parse "#{year}-#{month}-01"
    finish = month.to_i < 12 ? start.change(month: (start.month + 1)) : start.change(month: 1, year: (start.year + 1))
    where("start >= ? AND start < ?", start, finish)
  }
  scope :will_happen_in_two_days, -> {
    next_day = Time.zone.now + 1.day
    participatable.where('start > ? AND start < ?', next_day, (next_day + 1.day))
  }

  attr_reader :start_day, :start_time_12, :start_time_p
  attr_accessor :time_error
  before_validation do |event|
    errors.add(:start_time_12, 'Start time must be in the format ##:##') if event.time_error
    # todo. this should be added to start_time_12 rather than :base, but that's no good as "start time 12" is a poor name for users. fix
  end
  def assign_attributes(attrs)
    # if inputing start in parts (day and time), then combine them
    start_day = attrs.delete(:start_day)
    start_time = attrs.delete(:start_time_12)
    if start_time.present? && !(start_time.strip =~ /1?[0-9](:[0-9]{2})?/)
      start_time = nil
      self.time_error = true
    end
    start_time_p = (attrs.delete(:start_time_p) || 'AM').upcase.gsub('.', '')
    attrs[:start] = "#{start_day} #{start_time} #{start_time_p}" if attrs[:start].blank? && start_day.present? && start_time.present?
    # this is needed because during mass assignment, we can't guarantee that :start will be set before :duration
    dur = attrs.delete(:duration)
    super(attrs)
    self.duration = dur
  end
  def start_time_12 # start time using 12-hour clock
    start.present? ? start.strftime('%l:%M').strip : nil
  end
  def start_time_p
    start.present? ? start.strftime('%p') : nil
  end
  def duration=(timespan)
    if start.present? && timespan.present? && timespan.to_i > 0
      self.finish = start + timespan.to_i
    else
      nil
    end
  end
  def duration
    (start.present? && finish.present?) ? (finish - start).round : nil
  end
  def duration_hours
    duration.present? ? (duration / 3600) : nil
  end

  def past?
    finish.present? ? finish < Time.zone.now : nil
  end
  def time_until
    start.present? ? start - Time.zone.now : nil
  end
  def hours_until
    start.present? ? (time_until / 1.hour).round : nil
  end

  def awaiting_approval?
    !past? && proposed? && coordinator && start
  end

  include ActionView::Helpers::TextHelper # needed for truncate()
  def display_name
    return name if name.present?
    return truncate(description, length: 50, separator: ' ') if description.present?
    return truncate(address.gsub(/(\n|\r)+/, ', '), length: 50, separator: ' ') if address.present?
    return start.strftime('%B %e %Y, %l:%M %p').gsub('  ', ' ') if start.present?
    '(untitled event)'
  end

  def can_have_participants?
    start.present? && coordinator.present? && !proposed?
  end
  # next two methods: whether a participant *could* participate in the event, ignoring whether the event is full
  def can_accept_participants?
    can_have_participants? && approved? && (time_until > 2.hours) # todo: allow configurability of time_until threshhold
  end
  def participatable_by?(user)
    can_accept_participants? && (user != coordinator) && user.has_role?(:participant) && !event_users.find_or_initialize_by(user_id: user.id).denied?
  end

  def self.ical_date(datetime)
    datetime.strftime '%Y%m%dT%H%M00Z'
  end

  def to_ical(host = nil)
    vevent = Icalendar::Event.new
    vevent.klass = 'PRIVATE'
    vevent.url = Rails.application.routes.url_helpers.event_url(self, host: host) unless host.nil?
    vevent.created = self.class.ical_date created_at
    vevent.last_modified = self.class.ical_date updated_at
    vevent.dtstart = self.class.ical_date start
    vevent.dtend = self.class.ical_date finish
    vevent.summary = name if name
    desc = description || ''
    unless host.nil?
      desc += "\n\n" unless desc.blank? # is this working?
      desc += vevent.url
    end
    vevent.description desc if desc.present?
    if cancelled?
      vevent.status = 'CANCELLED'
    elsif can_have_participants?
      vevent.status = 'CONFIRMED'
    else
      vevent.status = 'TENTATIVE'
    end
    vevent.add_contact(coordinator.name) if coordinator # todo: replace with organizer property?
    vevent.geo = coords.join(',') if coords
    vevent.location = address if address
    vevent
  end

  # this method identical to that in model user.rb
  def coords
    (lat.present? && lng.present?) ? [lat, lng] : nil
  end

  # participant methods

  def participants_needed
    # this number should never be less than zero anyway, but the .max ensures that
    [min - participants.count, 0].max
  end
  def remaining_spots
    return true unless max
    # this number should never be less than zero anyway, but the .max ensures that
    [max - participants.count, 0].max
  end
  def full?
    max.present? && participants.reload.length >= max
  end

  attr_accessor :max_was_changed, :min_was_changed
  before_save do |event| # needed by after_save
    event.max = nil if event.max.blank?
    event.max_was_changed = event.max_changed?
    event.min_was_changed = event.min_changed?
    true
  end
  after_save do |event|
    # check against max
    if event.max_was_changed && event.can_accept_participants?
      if !event.full? && event.waitlisted.any?
        event.add_from_waitlist
      elsif event.max && event.participants.count > event.max
        event.remove_excess_participants
      end
    end
    # update cached participant info
    if event.max_was_changed || event.min_was_changed
      event.calculate_participants
    end
  end

  def calculate_participants # two methods that cache info to make sql queries easier
    has = event_users.where(status: EventUser.statuses_array(:attending, :attended)).reload.count
    self.below_min = has < min
    self.reached_max = max.present? && has >= max
    # using update_columns to avoid doing validations and callbacks
    update_columns(below_min: below_min, reached_max: reached_max) if changed?
  end

  # in these two methods, need to .to_a the sql results so that after we change the records, the query isn't re-executed when we want to email those we just changed
  def add_from_waitlist
    return false if past? || cancelled?
    spots = remaining_spots
    return false if !remaining_spots || remaining_spots == 0
    people = waitlisted.to_a
    if spots.is_a?(Integer) && people.length > spots # can't add in everyone, must choose
      # putting people who have no other events first while preserving the existing order as a secondary order
      people = people.partition{|u| u.events.none? }
      people = people.first + people.second
    end
    people.reject!{|u| !participatable_by? u} # checks that for instance, user's role of 'participant' hasn't been lost since getting on the waitlist
    people = people[0..(spots-1)] if spots.is_a?(Integer)
    if people.any?
      event_users.where(user_id: people.map{|u| u.id}).update_all status: EventUser.statuses[:attending]
      EventMailer.attend(self, people).deliver
    end
  end
  def remove_excess_participants # assumes there is an excess, so doesn't check that
    eus = event_users.where(status: EventUser.statuses[:attending]).order('event_users.updated_at DESC').limit(participants.count - max).to_a
    EventUser.where(id: eus.map{|eu| eu.id}).update_all status: EventUser.statuses[:waitlisted]
    EventMailer.unattend(self, eus.map{|eu| eu.user}, 'max_changed').deliver
  end

  def attend(user)
    event_users.where(user_id: user.id).first_or_initialize.attend
  end
  def unattend(user)
    event_users.where(user_id: user.id).first_or_initialize.unattend
  end

  def suggested_invitations # number of people that should be invited
    return 0 if !invitable? || full?
    response_rate = 0.1 # complete guess, and of course won't be the same for every org
    expected_from_invitations = event_users.where(status: EventUser.statuses[:invited]).count * response_rate * 0.8
    # 0.8 above is largely arbitrary, but the point is that the response rate of already sent invitations will be < response_rate as some will have been looked at and ignored
    reciprocal_rate = 1 / response_rate
    at_leasts = []
    at_leasts << (remaining_spots * reciprocal_rate) - expected_from_invitations if max
    at_leasts << (participants_needed * reciprocal_rate) - expected_from_invitations if min > 0
    return at_leasts.push(0).max.round if at_leasts.any?
    10 # not really based on anything, but gotta have some number here
  end
  def invitable?
    can_accept_participants? && coords
  end

  def invite(users)
    n = 0
    [*users].uniq.each do |participant|
      eu = event_users.create user: participant, status: :invited
      if eu.valid?
        Invitation.create event: self, user: participant
        n += 1
      end
    end
    n
  end

  def take_attendance(attended_eu_ids) # eu_ids which exist but are not passed in are no shows
    eus = event_users.where status: EventUser.statuses_array(:attending, :attended, :no_show)
    eus.each{|eu| eu.update status: attended_eu_ids.include?(eu.id) ? :attended : :no_show}
  end

  private

    # this method identical to that in model user.rb
    def geocode
      geo = Geokit::Geocoders::MultiGeocoder.geocode address.gsub(/\n/, ', ')
      if geo.success
        self.lat, self.lng = geo.lat, geo.lng
      else
        errors.add(:address, 'Problem locating address')
      end
    end

end