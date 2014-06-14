class DeviseMailer < Devise::Mailer # https://github.com/plataformatec/devise/blob/master/app/mailers/devise/mailer.rb

  default from: "#{Configurable.title} <#{Configurable.email}>", reply_to: "#{Configurable.title} <#{Configurable.email}>"

  layout 'event_mailer' # this is actually the general layout for all mail

end