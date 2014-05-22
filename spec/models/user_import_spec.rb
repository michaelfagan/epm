require 'spec_helper'

# testing same model as in user_spec.rb, but splitting tests of import feature into a separate file

describe User do

  it "imports one user with just an email address" do
    rows = [
        ['email'],
        ['foo@example.com']
      ]
      imported = User.import [ ['email'], ['foo@example.com'] ]
      expect(imported).to eq 1
      expect(User.find_by email: 'foo@example.com').not_to be_nil
  end

  it "imports multiple users" do
    rows = [
        ['email'],
        ['foo@example.com'],
        ['foo2@example.com']
      ]
      imported = User.import rows
      expect(imported).to eq 2
      expect(User.find_by email: 'foo@example.com').not_to be_nil
      expect(User.find_by email: 'foo2@example.com').not_to be_nil
  end

  it "imports data from multiple columns" do
    rows = [
        ['email', 'name'],
        ['foo@example.com', 'Joeyjoejoe']
      ]
      imported = User.import rows
      expect(imported).to eq 1
      u = User.find_by email: 'foo@example.com'
      expect(u.name).to eq 'Joeyjoejoe'
  end

  context "sanitizing input" do

    it "imports nothing for empty input" do
      rows = []
      expect(User.import rows).to eq 0
      rows = [ [], [] ]
      expect(User.import rows).to eq 0
      rows = [ [nil, nil], [nil, nil] ]
      expect(User.import rows).to eq 0
    end

    it "ignores unknown columns" do
      rows = [
          ['email', 'age'],
          ['foo@example.com', '35']
        ]
        imported = User.import rows
        expect(imported).to eq 1
        expect(User.find_by email: 'foo@example.com').not_to be_nil
    end

    it "ignores column order" do
      rows = [
          ['age', 'email'],
          ['35', 'foo@example.com']
        ]
        imported = User.import rows
        expect(imported).to eq 1
        expect(User.find_by email: 'foo@example.com').not_to be_nil
    end

    it "ignores header rows" do
      rows = [
          ['User List'],
          [],
          ['email', 'age'],
          ['foo@example.com', '35']
        ]
        imported = User.import rows
        expect(imported).to eq 1
        expect(User.find_by email: 'foo@example.com').not_to be_nil
    end

    it "ignores blank rows" do
      rows = [
          ['email'],
          ['foo@example.com'],
          [],
          ['foo2@example.com']
        ]
        imported = User.import rows
        expect(imported).to eq 2
        expect(User.find_by email: 'foo@example.com').not_to be_nil
        expect(User.find_by email: 'foo2@example.com').not_to be_nil
    end

    it "handles missing columns" do
      rows = [
          ['email', 'name', 'age'],
          ['foo@example.com'],
          ['foo2@example.com', 'Joeyjoejoe']
        ]
      imported = User.import rows
      expect(imported).to eq 2
      expect(User.find_by email: 'foo@example.com').not_to be_nil
      joe = User.find_by email: 'foo2@example.com'
      expect(joe.name).to eq 'Joeyjoejoe'
    end

    it "ignores invalid data" do
      rows = [
          ['email'],
          ['foo at example.com'],
          ['foo2@example.com']
        ]
        imported = User.import rows
        expect(imported).to eq 1
        expect(User.find_by email: 'foo2@example.com').not_to be_nil
    end

  end

  context "attributes" do

    context "email" do

      it "parses lowercase, unhyphenated" do
        imported = User.import [ ['email'], ['foo@example.com'] ]
        expect(imported).to eq 1
        expect(User.find_by email: 'foo@example.com').not_to be_nil
      end

      it "parses mixed cased, hyphenated, verbose" do
        imported = User.import [ ['E-Mail Address'], ['foo@example.com'] ]
        expect(imported).to eq 1
        expect(User.find_by email: 'foo@example.com').not_to be_nil
      end

    end

    context "name" do

      it "parses name" do
        imported = User.import [ ['email', 'name'], ['foo@example.com', 'Joeyjoejoe'] ]
        expect(imported).to eq 1
        expect(User.find_by(email: 'foo@example.com').name).to eq 'Joeyjoejoe'
      end

      it "parses mixed case, verbose" do
        imported = User.import [ ['email', 'Full Name'], ['foo@example.com', 'Joeyjoejoe'] ]
        expect(imported).to eq 1
        expect(User.find_by(email: 'foo@example.com').name).to eq 'Joeyjoejoe'
      end

      it "parses split into two, mixed case" do
        imported = User.import [ ['email', 'First name', 'Last name'], ['foo@example.com', 'Joe', 'Smith'] ]
        expect(imported).to eq 1
        expect(User.find_by(email: 'foo@example.com').name).to eq 'Joe Smith'
      end

      it "parses split into two, lowercase, alternate word separator" do
        imported = User.import [ ['email', 'first_name', 'last_name'], ['foo@example.com', 'Joe', 'Smith'] ]
        expect(imported).to eq 1
        expect(User.find_by(email: 'foo@example.com').name).to eq 'Joe Smith'
      end

      it "parses split into two, capitals, reverse order, alternate wording" do
        imported = User.import [ ['email', 'LAST', 'FIRST'], ['foo@example.com', 'Smith', 'Joe'] ]
        expect(imported).to eq 1
        expect(User.find_by(email: 'foo@example.com').name).to eq 'Joe Smith'
      end

      it "parses split into two, separated, mixed case, alternate wording" do
        imported = User.import [ ['fName', 'email', 'lName'], ['Joe', 'foo@example.com', 'Smith'] ]
        expect(imported).to eq 1
        expect(User.find_by(email: 'foo@example.com').name).to eq 'Joe Smith'
      end

    end

    context "phone number" do

      it "parses phone" do
        imported = User.import [ ['email', 'phone'], ['foo@example.com', '123 456-7890'] ]
        expect(imported).to eq 1
        expect(User.find_by(email: 'foo@example.com').phone).to eq '123 456-7890'
      end

      it "parses with alternate wording, capitalized" do
        imported = User.import [ ['email', 'TEL'], ['foo@example.com', '123 456-7890'] ]
        expect(imported).to eq 1
        expect(User.find_by(email: 'foo@example.com').phone).to eq '123 456-7890'
      end

      it "parses with alternate wording, mixed case" do
        imported = User.import [ ['email', 'Telephone_Number'], ['foo@example.com', '123 456-7890'] ]
        expect(imported).to eq 1
        expect(User.find_by(email: 'foo@example.com').phone).to eq '123 456-7890'
      end


    end

    context "address" do

      it "parses address" do
        imported = User.import [ ['email', 'address'], ['foo@example.com', '123 Fake Street, City'] ]
        expect(imported).to eq 1
        expect(User.find_by(email: 'foo@example.com').address).to eq '123 Fake Street, City'
      end

      it "parses with mixed case, verbosity" do
        imported = User.import [ ['email', 'Home Address'], ['foo@example.com', '123 Fake Street, City'] ]
        expect(imported).to eq 1
        expect(User.find_by(email: 'foo@example.com').address).to eq '123 Fake Street, City'
      end

      it "parses with newlines" do
        imported = User.import [ ['email', 'address'], ['foo@example.com', "123 Fake Street\nCity"] ]
        expect(imported).to eq 1
        expect(User.find_by(email: 'foo@example.com').address).to eq "123 Fake Street\nCity"
      end

    end

  end

  context "security" do

    it "generates random passwords by default" do
      expect(User.import [['email'], ['foo@example.com']]).to eq 1
      expect(User.find_by(email: 'foo@example.com').valid_password? 'foo@example.com').not_to be_true
    end

    it "uses email addresses for passwords in less secure mode" do
      expect(User.import [['email'], ['foo@example.com']], false).to eq 1
      expect(User.find_by(email: 'foo@example.com').valid_password? 'foo@example.com').to be_true
    end

  end

end