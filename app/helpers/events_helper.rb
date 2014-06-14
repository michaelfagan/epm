module EventsHelper

  def date(datetime)
    # this method needs to be kept in synch with js-formatted date in events/_form.html.erb
    datetime.strftime '%A %B %e, %Y'
  end

  def time(datetime)
    datetime.strftime('%l:%M %p').strip
  end

  def relative_time(event)
    str = time_ago_in_words event.start
    event.past? ? "#{str} ago" : "in #{str}"
  end

  def month_calendar(events)
    html_options = { class: 'month_calendar' }
    html_options[:data] = { map: true } if events.find{|e|e.coords}
    content_tag 'section', html_options do
      # calls method from simple_calendar gem with particular options
      options = {
        time_selector: 'start',
        class: nil,
        prev_text: '«<span> prev<span>ious</span></span>'.html_safe,
        next_text: '<span>next </span>»'.html_safe
      }
      if can? :create, Event
        add_link = lambda{ |date| link_to '+', new_event_path(start_day: date), class: 'add', title: "add #{Configurable.event} on this day" }
        options[:empty_date] = add_link
        options[:not_empty_date] = add_link
      end
      calendar events, options do |event|
        yield(event)
      end
    end
  end

end

# overriding header method for calendar so that we can insert the number of events during that month
# for now relies on using instance variable @events
# original: https://github.com/excid3/simple_calendar/blob/master/lib/simple_calendar/view_helpers.rb
module SimpleCalendar
  module ViewHelpers
    def month_header(selected_month, options)
      content_tag :h2 do
        previous_month = selected_month.advance :months => -1
        next_month = selected_month.advance :months => 1
        tags = []
        tags << month_link(options[:prev_text], previous_month, options[:params], {:class => "previous-month"})
        tags << "#{I18n.t("date.month_names")[selected_month.month]} #{selected_month.year} &ndash; #{pluralize @events.length, Configurable.event.titlecase}"
        tags << month_link(options[:next_text], next_month, options[:params], {:class => "next-month"})
        tags.join.html_safe
      end
    end
  end
end