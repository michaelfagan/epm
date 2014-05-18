module ApplicationHelper

  def title(str)
    content_for :title, str
  end

  require 'rails_rinku'
  def paragraphs(text)
    simple_format auto_link text
  end
  def with_br(str)
    str.gsub(/\n/, '<br>').html_safe
  end

  def clear
    content_tag 'div', nil, class: 'clearfix'
  end

  def start_cols
    '<div class="cols"><div class="colA">'.html_safe
  end
  def next_col
    '</div><div class="colB">'.html_safe
  end
  def end_cols
    "</div></div>#{clear}".html_safe
  end

  def cancel(str = 'Cancel', html_options = {})
    submit str, html_options.merge(class: 'default')
  end
  def submit(str = 'Save', html_options = {})
    content_tag :button, html_options.merge(type: 'submit', name: 'commit', value: str) do
      str
    end
  end

  # overwrite to force using <button> instead of <input type="submit">
  def button_to(name = nil, options = nil, html_options = nil, &block)
    super(options, html_options) do
      name
    end
  end

  # overwrite form helpers to have inputs auto-size to their content
  def form_for(name, *args, &block)
    options = args.extract_options!
    # substitute our own form builder for the default one
    super(name, *(args << options.merge(:builder => StandardFormBuilder)), &block)
  end
  def text_field_tag(name, value = nil, options = {})
    if options['type'] != 'number' && options['type'] != 'hidden'
      options[:size] = 25 unless options.has_key? :size
      options[:size] = [[options[:size], (value.to_s.length+3)].max, 100].min unless value.nil?
      options['data-default_size'] = 25 unless options.has_key? :maxlength
    end
    super(name, value, options)
  end

end


class StandardFormBuilder < ActionView::Helpers::FormBuilder

  def self.create_tagged_field(method_name, default_size = 25)
    define_method(method_name) do |label, *args|
      args[0] = {} unless args.any?
      # smart length expands from default (up to a max) based on the content
      args[0][:size] = default_size unless args[0].has_key? :size
      args[0][:size] = [[args[0][:size], (@object[label].to_s.length+3)].max, 100].min unless @object.new_record? || @object[label].nil?
      args[0]['data-default_size'] = default_size unless args[0].has_key? :maxlength
      super(label, *args)
    end
  end
  create_tagged_field('text_field')
  create_tagged_field('email_field')
  create_tagged_field('password_field')
  create_tagged_field('phone_field')
  create_tagged_field('url_field', 52)

end
