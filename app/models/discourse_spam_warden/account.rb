# frozen_string_literal: true

module DiscourseSpamWarden
  class Account < ActiveRecord::Base
    self.table_name = "spam_warden_accounts"
    belongs_to :user
    validates :user_id, presence: true, uniqueness: true

    def owns_silence?
      return false if silence_history_id.blank? || !user.silenced?
      return false if user.silenced_till != silenced_till
      UserHistory
        .where(
          target_user_id: user_id,
          action: [UserHistory.actions[:silence_user], UserHistory.actions[:unsilence_user]],
        )
        .order(id: :desc)
        .pick(:id) == silence_history_id
    end
  end
end

# == Schema Information
#
# Table name: spam_warden_accounts
#
#  id                 :bigint           not null, primary key
#  allowed            :boolean          default(FALSE), not null
#  silenced_till      :datetime
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  allowed_by_id      :bigint
#  silence_history_id :bigint
#  user_id            :bigint           not null
#
# Indexes
#
#  index_spam_warden_accounts_on_user_id  (user_id) UNIQUE
#
