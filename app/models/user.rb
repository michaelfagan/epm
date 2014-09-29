class User < ActiveRecord::Base

  devise :database_authenticatable, :registerable, :confirmable, :recoverable, :rememberable, :trackable, :validatable

  strip_attributes
  before_create do |user|
    if user.email.present? && user.email.include?('@') && user.name.blank?
      user.name = user.email.split('@').first.gsub(/(\.|-|_|\d)+/, ' ').strip.titlecase
    end
    true
  end

  def has_full_profile?
    name.present? && description.present? && email.present? && phone.present? && address.present? && lat.present? && lng.present?
  end

  def self.csv
    CSV.generate force_quotes: true do |csv|
      csv << ['id', 'name', 'email', 'phone number', 'joined', "events attended as #{Configurable.participant.indefinitize}", 'roles', 'description']
      all.each do |user|
        csv << [user.id, user.name, user.email, user.phone, user.created_at.to_date.to_s, user.participated_events.count, user.roles.map{|r| Configurable.send(r.name)}.join(', '), user.description]
      end
    end
  end

  # rows is an array of arrays, e.g. from parsing a csv file
  # returns the number of users imported
  def self.import(rows, secure = true)

    # sanitize input and such. does good stuff but fails if header row is missing columns
    rows.reject!{|r| r.length.zero? || (r.uniq.length == 1 && r.first.blank?) } # remove blank rows
    return 0 unless rows.any?
    # remove title rows
    number_of_cols = rows.map{|r|r.length}.sort.last
    return 0 unless number_of_cols > 0
    first_ok_row = rows.index{|r| r.length == number_of_cols }
    rows = rows[first_ok_row..-1]
    # go through each row and append blank columns if it is missing any
    rows.each do |row|
      row += Array.new(number_of_cols - row.length) if row.length < number_of_cols
    end
    # split off header
    header = rows.first.map{|c| c.downcase }
    rows = rows[1..-1]

    # find which column has which info
    # email (primary key)
    fields = {}
    fields[:email] = header.index{|c| c =~ /e(-)?mail/ }
    return 0 unless fields[:email]
    # name (first, check for names split into first and last)
    fname_col = header.index{|c| (c =~ /f(irst)?.?name/) || c == 'first' }
    if fname_col
      lname_col = header.index{|c| (c =~ /l(ast)?.?name/) || c == 'last' }
      if lname_col
        rows.each {|r| r << [r[fname_col], r[lname_col]].join(' ') }
        fields[:name] = rows.first.length - 1
      end
    end
    unless fields[:name]
      fields[:name] = header.index{|c| c.include? 'name' }
    end
    # password
    if secure
      rows.each {|r| r << Devise.friendly_token.first(8) }
      fields[:password] = rows.first.length - 1
    else
      fields[:password] = fields[:email]
    end
    # more fields
    fields[:phone] = header.index{|c| c.include?('phone') || c.include?('tel') }
    fields[:address] = header.index{|c| c.include?('address') && c !~ /e(-)?mail/ }
    fields.reject!{|k, v| !v} # remove fields which aren't actually there

    # add them
    new_users = 0
    rows.each do |row|
      u = User.new
      fields.each {|attr_name, col_i| u.send "#{attr_name}=", row[col_i] }
      u.confirmed_at = Time.zone.now # auto-confirm users. also means they won't get sent confirmation emails
      new_users += 1 if u.save
    end
    new_users

  end

  # this section identical to that in model event.rb
  acts_as_mappable
  attr_accessor :no_geocode # force geocoding to not happen. used for testing
  after_validation :geocode, if: "!no_geocode && address_changed? && address.present? && (lat.blank? || lng.blank?)"
  validates :lat, numericality: {greater_than_or_equal_to: -90, less_than_or_equal_to: 90}, allow_nil: true
  validates :lng, numericality: {greater_than_or_equal_to: -180, less_than_or_equal_to: 180}, allow_nil: true


  scope :by_name, -> { order :name }
  scope :geocoded, -> { where.not lat: nil }
  scope :search, ->(q) {
    like = Rails.configuration.database_configuration[Rails.env]["adapter"] == 'postgresql' ? 'ILIKE' : 'LIKE'
    where("users.email #{like} ? OR users.name #{like} ?", "%#{q}%", "%#{q}%")
  }
  scope :roleless, -> { where 'users.id NOT IN (SELECT DISTINCT user_id FROM roles)' }
  # todo: consider refactoring these to automatically have a scope for every role
  scope :admins, -> { joins("INNER JOIN roles ON roles.user_id = users.id AND roles.name = #{Role.names[:admin]}") }
  scope :coordinators, -> { joins("INNER JOIN roles ON roles.user_id = users.id AND roles.name = #{Role.names[:coordinator]}") }
  scope :participants, -> { joins("INNER JOIN roles ON roles.user_id = users.id AND roles.name = #{Role.names[:participant]}") }
  def self.coordinators_not_taking_attendance
    # get the ids of events needing attendance taken and more 3 days old (note: query is executed as a subquery of the next query)
    event_ids = Event.needing_attendance_taken.where("finish < ?", 3.days.ago).reorder(nil).select 'events.id'
    # get the coordinators of those events, orderded by how many events they haven't done attendance for
    coordinator_ids = Event.where("id IN (#{event_ids.to_sql})").group(:coordinator_id).reorder('COUNT(events.id) DESC').select(:coordinator_id).pluck :coordinator_id
    coordinators = User.where(id: coordinator_ids).to_a
    coordinator_ids.map{|uid| coordinators.find{|c| c.id == uid} }
  end
  scope :not_involved_in_by_distance, ->(event) {
    return none unless event.coords
    geocoded.by_distance(origin: event.coords)
      .where.not("users.id IN (#{EventUser.where(event_id: event.id).select(:user_id).to_sql})")
  }
  scope :participated_in_no_events, -> {
    user_ids = EventUser.where(status: EventUser.statuses_array(:attending, :attended))
      .joins(:event).where("events.status = #{Event.statuses[:approved]}").select('event_users.user_id')
    where.not "users.id IN (#{user_ids.to_sql})"
  }

  has_many :event_users, dependent: :destroy
  has_many :coordinating_events, -> { where.not(status: Event.statuses[:cancelled]) }, class_name: 'Event', foreign_key: 'coordinator_id'
  has_many :participated_events, -> { # events where a user was marked as having attended (and thus in the past and not cancelled)
      where('event_users.status' => EventUser.statuses[:attended]).where('events.status = ?', Event.statuses[:approved])
    }, through: :event_users, source: :event
  def events # where the user is a participant or the coordinator
    Event.not_cancelled
      .joins("LEFT JOIN event_users ON events.id = event_users.event_id AND event_users.status IN (#{EventUser.statuses_array(:attending, :attended).join(', ')})")
      .where("events.coordinator_id = ? OR event_users.user_id = ?", id, id)
      .distinct
  end
  def open_invites # upcoming events the user has been invited to
    Event.not_past.not_cancelled.joins(:event_users)
      .where(
        'event_users.status' => EventUser.statuses[:invited],
        'event_users.user_id' => id
      )
  end
  def potential_events # upcoming events where waitlisted or requested to attend
    Event.not_past.not_cancelled.joins(:event_users)
      .where(
        'event_users.status' => EventUser.statuses_array(:waitlisted, :requested),
        'event_users.user_id' => id
      )
  end
  def participating_events # upcoming events the participant plans to attend
    Event.not_past.not_cancelled.joins(:event_users)
      .where(
        'event_users.status' => EventUser.statuses[:attending],
        'event_users.user_id' => id
      )
  end

  has_many :roles, dependent: :destroy
  accepts_nested_attributes_for :roles
  attr_accessor :no_roles
  after_create :set_default_role, if: "roles.empty? && !no_roles"
  def set_default_role
   if self.class.count == 1
      self.roles.create name: :admin
    else
      self.roles.create name: :participant
    end
  end
  def has_role?(role_name)
    !self.roles.find{|r| r.send "#{role_name}?" }.nil?
  end
  def has_any_role?(*roles)
    roles.each do |role|
      return true if has_role?(role)
    end
    false
  end

  def display_name
    name || '(no name given)'
  end

  def avatar(size = :small)
    sizes = {small: 48, large: 80}
    "http://gravatar.com/avatar/#{CGI.escape(Digest::MD5.hexdigest(email.downcase))}?s=#{sizes[size]}&d=mm"
  end

  def ability # allows checking permissions for this user rather than the current
    @ability ||= Ability.new(self)
  end

  # this method identical to that in model event.rb
  def coords
    (lat.present? && lng.present?) ? [lat, lng] : nil
  end

  private

    # this method identical to that in model event.rb
    def geocode
      geo = Geokit::Geocoders::MultiGeocoder.geocode address.gsub(/\n/, ', ')
      self.lat, self.lng = geo.lat, geo.lng if geo.success
    end


end