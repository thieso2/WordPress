# frozen_string_literal: true

require "rails_helper"

# Publishing::Post's edit lock — the port of wp_set_post_lock() / wp_check_post_lock()
# (wp-admin/includes/post.php:1760 / :1715) and the 150 s `wp_check_post_lock_window`
# (:1737), promoted from `_edit_lock` postmeta to columns (AD-03, db/migrate/20260823000300).
RSpec.describe Publishing::Post, "edit lock" do
  include ActiveSupport::Testing::TimeHelpers

  let(:alice) { Identity::User.create!(login: "alice", email: "alice@example.com", nicename: "alice", display_name: "Alice", password: "pw-alice-1") }
  let(:bob)   { Identity::User.create!(login: "bob", email: "bob@example.com", nicename: "bob", display_name: "Bob", password: "pw-bob-1") }
  let(:post)  { Publishing::Article.create!(author: alice, status: :draft, title: "T", content: "", excerpt: "") }

  it "wp_check_post_lock_window is 150 seconds, unfiltered (:1737)" do
    expect(described_class::LOCK_WINDOW).to eq(150.seconds)
  end

  describe "#lock_editing!" do
    it "stamps <now>:<actor> and returns [time, actor] (wp_set_post_lock :1760)" do
      freeze_time do
        result = post.lock_editing!(actor: alice)
        expect(result).to eq([Time.current, alice])
        expect(post.reload.edit_lock_by_id).to eq(alice.id)
        expect(post.edit_lock_at).to eq(Time.current)
      end
    end

    it "returns false with no actor (:1767, `0 === $user_id`)" do
      expect(post.lock_editing!(actor: nil)).to be(false)
    end

    it "does NOT touch modified_at or record a revision — a lock is not an edit" do
      post.update!(title: "T2", actor: alice)
      before = post.reload.modified_at
      expect { post.lock_editing!(actor: alice) }.not_to change { post.revisions.count }
      expect(post.reload.modified_at).to eq(before)
    end
  end

  describe "#edit_lock_holder_if_live" do
    it "reports the holder to a DIFFERENT actor within the window (:1739)" do
      post.lock_editing!(actor: alice)
      expect(post.edit_lock_holder_if_live(actor: bob)).to eq(alice)
      expect(post.locked_against?(bob)).to be(true)
    end

    it "reports nobody to the holder themselves (`get_current_user_id() !== $user`)" do
      post.lock_editing!(actor: alice)
      expect(post.edit_lock_holder_if_live(actor: alice)).to be_nil
      expect(post.locked_against?(alice)).to be(false)
    end

    it "reports nobody once the lock is older than the window (:1739)" do
      post.lock_editing!(actor: alice)
      travel(described_class::LOCK_WINDOW + 1.second) do
        expect(post.edit_lock_holder_if_live(actor: bob)).to be_nil
      end
    end

    it "reports nobody when the holder's account is gone (:1732)" do
      post.lock_editing!(actor: bob)
      bob.destroy! # ON DELETE SET NULL clears edit_lock_by_id
      expect(post.reload.edit_lock_holder_if_live(actor: alice)).to be_nil
    end

    it "reports nobody on an unlocked post" do
      expect(post.edit_lock_holder_if_live(actor: bob)).to be_nil
    end
  end

  describe "#steal_lock! (the take-over path)" do
    it "reassigns the lock to the arriving user (get-post-lock → wp_set_post_lock)" do
      post.lock_editing!(actor: alice)
      post.steal_lock!(actor: bob)
      expect(post.reload.edit_lock_by_id).to eq(bob.id)
      expect(post.edit_lock_holder_if_live(actor: alice)).to eq(bob)
    end
  end

  describe "#release_lock!" do
    it "clears the lock only for its holder" do
      post.lock_editing!(actor: alice)
      expect(post.release_lock!(actor: bob)).to be(false)
      expect(post.release_lock!(actor: alice)).to be(true)
      expect(post.reload.edit_lock_by_id).to be_nil
      expect(post.edit_lock_at).to be_nil
    end
  end
end
