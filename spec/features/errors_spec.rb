require 'spec_helper'

describe "Errors" do

  it "displays a 404" do
    ['/users/foo', '/events/barr'].each do |path|
      visit path
      expect(page).to have_content 'Not Found'
      expect(status_code).to eq 404
    end
  end

end