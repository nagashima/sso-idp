# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SignupTicketService do
  let(:email) { 'test@example.com' }
  let(:login_challenge) { 'challenge_xyz123' }

  before do
    # テストデータクリーンアップ
    SignupTicket.destroy_all
  end

  describe '.create_ticket' do
    context '通常の会員登録フロー（login_challenge なし）' do
      it 'チケットを作成できる' do
        ticket = SignupTicketService.create_ticket(email: email)

        expect(ticket).to be_persisted
        expect(ticket.email).to eq email
        expect(ticket.token).to match(/\A[0-9a-f]{64}\z/)
        expect(ticket.expires_at).to be > Time.current
        expect(ticket.expires_at).to be < 25.hours.from_now
        expect(ticket.confirmed_at).to be_nil
        expect(ticket.login_challenge).to be_nil
      end
    end

    context 'SSOフロー中の会員登録（login_challenge あり）' do
      it 'チケットを作成できる' do
        ticket = SignupTicketService.create_ticket(
          email: email,
          login_challenge: login_challenge
        )

        expect(ticket).to be_persisted
        expect(ticket.email).to eq email
        expect(ticket.login_challenge).to eq login_challenge
      end
    end

    context '無効なメールアドレスの場合' do
      it 'ActiveRecord::RecordInvalidをraiseする' do
        expect {
          SignupTicketService.create_ticket(email: 'invalid_email')
        }.to raise_error(ActiveRecord::RecordInvalid)
      end
    end
  end

  describe '.find_valid_ticket' do
    context 'メール確認済み かつ 有効期限内のチケット' do
      let!(:ticket) do
        SignupTicket.create!(
          email: email,
          token: SignupTicket.generate_token,
          expires_at: 1.hour.from_now,
          confirmed_at: Time.current
        )
      end

      it 'チケットを返す' do
        result = SignupTicketService.find_valid_ticket(ticket.token)

        expect(result).to eq ticket
      end
    end

    context 'メール未確認のチケット' do
      let!(:ticket) do
        SignupTicket.create!(
          email: email,
          token: SignupTicket.generate_token,
          expires_at: 1.hour.from_now,
          confirmed_at: nil  # 未確認
        )
      end

      it 'nilを返す' do
        result = SignupTicketService.find_valid_ticket(ticket.token)

        expect(result).to be_nil
      end
    end

    context '有効期限切れのチケット' do
      let!(:ticket) do
        SignupTicket.create!(
          email: email,
          token: SignupTicket.generate_token,
          expires_at: 1.hour.ago,  # 期限切れ
          confirmed_at: Time.current
        )
      end

      it 'nilを返す' do
        result = SignupTicketService.find_valid_ticket(ticket.token)

        expect(result).to be_nil
      end
    end

    context '存在しないトークン' do
      it 'nilを返す' do
        result = SignupTicketService.find_valid_ticket('nonexistent_token')

        expect(result).to be_nil
      end
    end
  end

  describe '.mark_as_confirmed' do
    context '有効なチケット' do
      let!(:ticket) do
        SignupTicket.create!(
          email: email,
          token: SignupTicket.generate_token,
          expires_at: 1.hour.from_now,
          confirmed_at: nil
        )
      end

      it 'confirmed_atを設定してtrueを返す' do
        expect {
          result = SignupTicketService.mark_as_confirmed(ticket.token)
          expect(result).to be true
        }.to change { ticket.reload.confirmed_at }.from(nil)

        expect(ticket.confirmed_at).to be_within(1.second).of(Time.current)
      end
    end

    context '有効期限切れのチケット' do
      let!(:ticket) do
        SignupTicket.create!(
          email: email,
          token: SignupTicket.generate_token,
          expires_at: 1.hour.ago,
          confirmed_at: nil
        )
      end

      it 'falseを返す（confirmed_atは変更されない）' do
        result = SignupTicketService.mark_as_confirmed(ticket.token)

        expect(result).to be false
        expect(ticket.reload.confirmed_at).to be_nil
      end
    end

    context '存在しないトークン' do
      it 'falseを返す' do
        result = SignupTicketService.mark_as_confirmed('nonexistent_token')

        expect(result).to be false
      end
    end
  end

  describe '.mark_as_used' do
    let!(:ticket) do
      SignupTicket.create!(
        email: email,
        token: SignupTicket.generate_token,
        expires_at: 1.hour.from_now,
        confirmed_at: Time.current
      )
    end

    it 'チケットを削除する' do
      expect {
        SignupTicketService.mark_as_used(ticket)
      }.to change(SignupTicket, :count).by(-1)

      expect(SignupTicket.find_by(id: ticket.id)).to be_nil
    end
  end

  describe '.find_by_token' do
    let!(:ticket) do
      SignupTicket.create!(
        email: email,
        token: SignupTicket.generate_token,
        expires_at: 1.hour.from_now
      )
    end

    it 'チケットを返す（有効性チェックなし）' do
      result = SignupTicketService.find_by_token(ticket.token)

      expect(result).to eq ticket
    end

    it '存在しないトークンの場合nilを返す' do
      result = SignupTicketService.find_by_token('nonexistent_token')

      expect(result).to be_nil
    end
  end
end
