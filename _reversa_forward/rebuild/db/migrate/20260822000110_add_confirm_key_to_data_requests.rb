# frozen_string_literal: true

# auth.confirmaction (target_screens.md § Part 3) needs what the legacy kept in the
# user_request post's `post_password` (the hashed confirm key, wp-includes/user.php:5060)
# and read off `post_modified_gmt` (the key's issue instant, :5091). AD-02 split the
# request out of wp_posts; these are the two columns that split left behind.
class AddConfirmKeyToDataRequests < ActiveRecord::Migration[8.1]
  def change
    add_column :data_requests, :confirm_key_digest, :text
    add_column :data_requests, :confirm_key_sent_at, :timestamptz
  end
end
