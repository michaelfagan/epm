require "spec_helper"

describe DeviseMailer do

  # signature is set in the layout, no need to check every mailer
  it "includes the email signature" do
    setting = Configurable.find_or_initialize_by name: 'email_signature'
    setting.update value: 'Thanks for reading'
    mail = DeviseMailer.confirmation_instructions(create(:user), Devise.friendly_token.first(8))
    mail.body.parts.each do |part|
      expect(part.to_s).to match 'Thanks for reading'
    end
  end

end