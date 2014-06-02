class AdminMailer < ActionMailer::Base

  default from: "#{Configurable.title} <#{Configurable.email}>"

  def error_happened(exception, request = false)
    @exception = exception
    @request = request
    mail subject: "Error on #{Configurable.title}", to: Configurable.webmaster
  end

end