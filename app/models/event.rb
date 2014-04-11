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

  # todo : move this out of model into just view and controller
  attr_accessor :notify_of_changes # setting to false allows supressing email notifications; todo: move to controller

  has_many :event_users, dependent: :destroy
  has_many :participants, -> { where 'event_users.status' => [EventUser.statuses[:attending], EventUser.statuses[:attended]] }, through: :event_users, source: :user
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
  scope :not_attended_by, ->(user) {
    joins('LEFT JOIN event_users ON events.id = event_users.event_id')
    .where("events.id NOT IN (SELECT event_id FROM event_users WHERE user_id = ? AND status IN (#{EventUser.statuses[:attending]},#{EventUser.statuses[:attended]})) AND coordinator_id != ?", user.id, user.id)
    .distinct
  }
  scope :coordinatorless, -> { where coordinator: nil }
  scope :dateless, -> { where start: nil }
  scope :participatable, -> { where 'start IS NOT NULL AND coordinator_id IS NOT NULL AND events.status = ?', statuses[:approved] }
  scope :not_cancelled, -> { where 'events.status != ?', statuses[:cancelled] }
  scope :awaiting_approval, -> { not_past.where 'events.status = ? AND coordinator_id IS NOT NULL AND start IS NOT NULL', statuses[:proposed] }
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

  attr_reader :start_day, :start_time_12, :start_time_p
  attr_accessor :time_error
  before_validation do |event|
    errors.add(:base, 'Start time must be in the format ##:##') if event.time_error
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

  def awaiting_approval?
    !past? && proposed? && coordinator && start
  end

  include ActionView::Helpers::TextHelper # needed for truncate()
  def display_name(user = nil)
    return name if name.present?
    return truncate(description, length: 50, separator: ' ') if description.present?
    if address.present? && (!hide_specific_location || (user && user.ability.can?(:read_specific_location, self)) )
      return truncate(address, length: 50, separator: ' ') if address.present?
    end
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

  def coords(user = nil)
    return nil if lat.blank? || lng.blank?
    if !hide_specific_location || (user && user.ability.can?(:read_specific_location, self))
      return [lat, lng]
    end
    [lat.round(2), lng.round(2)]
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

  attr_accessor :max_was_changed
  before_save do |event|
    event.max = nil if event.max.blank?
    event.max_was_changed = event.max_changed?
    true
  end
  after_save :check_against_max, if: "max_was_changed && :can_accept_participants?"
  def check_against_max
    if !full? && waitlisted.any?
      add_from_waitlist
    elsif max && participants.count > max
      remove_excess_participants
    end
  end

  # in these two methods, need to .to_a the sql results so that after we change the records, the query isn't re-executed when we want to email those we just changed
  def add_from_waitlist
    return false if past? || cancelled?
    spots = remaining_spots
    return false if !remaining_spots || remaining_spots == 0
    eus = event_users.where(status: EventUser.statuses[:waitlisted]).order('event_users.updated_at')
    eus = eus.limit(spots) if spots.is_a?(Integer)
    eus = eus.to_a.select{|eu| participatable_by? eu.user } # checks that for instance, user's role of 'participant' hasn't been lost since getting on the waitlist
    if eus.any?
      EventUser.where(id: eus.map{|eu| eu.id}).update_all status: EventUser.statuses[:attending]
      EventMailer.attend(self, eus.map{|eu| eu.user}).deliver
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

  def invitable_participants
    # todo: take into account those who haven't been to any events yet
    invitable = User.participants
    if self.coords
      invitable = invitable.where.not(lat: nil).by_distance(origin: self.coords)
    else
      invitable = invitable.order('created_at DESC') # i.e. newest participants
    end
    exclude = []
    exclude << coordinator.id if coordinator
    event_users.select{|eu| eu.persisted?}.each{|eu| exclude << eu.user_id}
    invitable = invitable.where.not(id: exclude) if exclude.any?
    invitable
  end
  def self.max_invitable
    50
  end
  def suggested_invitations # number of people that should be invited
    return 0 if full? || !can_accept_participants?
    num = invitable_participants.limit(self.class.max_invitable).count
    num = [num, (max * 2)].min if max
    num
  end
  def invitable?
    can_accept_participants? && event_users.select{|eu| eu.persisted?}.none? && suggested_invitations > 0
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