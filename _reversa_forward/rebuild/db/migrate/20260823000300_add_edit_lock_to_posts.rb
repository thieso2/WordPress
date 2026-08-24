# frozen_string_literal: true

# AD-03: the editor's post lock, promoted from postmeta to real columns.
#
# The legacy kept two postmeta keys on the edited post (wp-admin/includes/post.php):
#   * `_edit_lock` — "<unix time>:<user id>", written by wp_set_post_lock() (:1760) and
#     read by wp_check_post_lock() (:1715). The lock is LIVE only while the timestamp is
#     within wp_check_post_lock_window() (150 s, :1737) of now and the holder is not the
#     current user; otherwise the post is editable and the lock is simply overwritten.
#   * `_edit_last` — the id of the user who last opened the editor, the fallback holder
#     when `_edit_lock` carries no user segment (:1730).
#
# Two nullable columns carry both. `edit_lock_at` is the `_edit_lock` timestamp and
# `edit_lock_by_id` its (and `_edit_last`'s) user — one column, because the target always
# writes the user segment, so the fallback path never differs from the primary one. The
# FK mirrors posts.author_id's ON DELETE SET NULL: a deleted user cannot hold a lock, and
# wp_check_post_lock() already treats a lock whose `get_userdata()` is gone as absent
# (:1732, `if ( ! get_userdata( $user ) ) return false`).
class AddEditLockToPosts < ActiveRecord::Migration[8.1]
  def up
    add_column :posts, :edit_lock_at, :timestamptz
    add_column :posts, :edit_lock_by_id, :bigint
    add_foreign_key :posts, :users, column: :edit_lock_by_id, on_delete: :nullify
    add_index :posts, :edit_lock_by_id, name: "posts_edit_lock_by", where: "edit_lock_by_id IS NOT NULL"
  end

  def down
    remove_index :posts, name: "posts_edit_lock_by"
    remove_foreign_key :posts, column: :edit_lock_by_id
    remove_column :posts, :edit_lock_by_id
    remove_column :posts, :edit_lock_at
  end
end
