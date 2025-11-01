require 'rails_helper'

RSpec.describe SignupTicket, type: :model do
  describe 'validations' do
    it { should validate_presence_of(:email) }
    it { should validate_presence_of(:token) }
    it { should validate_presence_of(:expires_at) }

    it 'validates email format' do
      ticket = SignupTicket.new(email: 'invalid-email', token: 'abc', expires_at: 1.hour.from_now)
      expect(ticket).not_to be_valid
      expect(ticket.errors[:email]).to be_present
    end

    it 'validates token uniqueness' do
      token = SecureRandom.hex(32)
      SignupTicket.create!(email: 'test@example.com', token: token, expires_at: 1.hour.from_now)

      duplicate = SignupTicket.new(email: 'other@example.com', token: token, expires_at: 1.hour.from_now)
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:token]).to be_present
    end
  end

  describe '.generate_token' do
    it 'generates a 64-character hex token' do
      token = SignupTicket.generate_token
      expect(token).to match(/\A[0-9a-f]{64}\z/)
    end

    it 'generates unique tokens' do
      token1 = SignupTicket.generate_token
      token2 = SignupTicket.generate_token
      expect(token1).not_to eq(token2)
    end
  end

  describe '#expired?' do
    it 'returns true when expires_at is in the past' do
      ticket = SignupTicket.new(expires_at: 1.hour.ago)
      expect(ticket.expired?).to be true
    end

    it 'returns false when expires_at is in the future' do
      ticket = SignupTicket.new(expires_at: 1.hour.from_now)
      expect(ticket.expired?).to be false
    end
  end

  describe '#confirmed?' do
    it 'returns true when confirmed_at is present' do
      ticket = SignupTicket.new(confirmed_at: Time.current)
      expect(ticket.confirmed?).to be true
    end

    it 'returns false when confirmed_at is nil' do
      ticket = SignupTicket.new(confirmed_at: nil)
      expect(ticket.confirmed?).to be false
    end
  end

  describe '#valid_for_signup?' do
    it 'returns true when confirmed and not expired' do
      ticket = SignupTicket.new(
        confirmed_at: Time.current,
        expires_at: 1.hour.from_now
      )
      expect(ticket.valid_for_signup?).to be true
    end

    it 'returns false when not confirmed' do
      ticket = SignupTicket.new(
        confirmed_at: nil,
        expires_at: 1.hour.from_now
      )
      expect(ticket.valid_for_signup?).to be false
    end

    it 'returns false when expired' do
      ticket = SignupTicket.new(
        confirmed_at: Time.current,
        expires_at: 1.hour.ago
      )
      expect(ticket.valid_for_signup?).to be false
    end

    it 'returns false when not confirmed and expired' do
      ticket = SignupTicket.new(
        confirmed_at: nil,
        expires_at: 1.hour.ago
      )
      expect(ticket.valid_for_signup?).to be false
    end
  end
end
