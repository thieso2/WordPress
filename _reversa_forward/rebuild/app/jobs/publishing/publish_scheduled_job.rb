# frozen_string_literal: true

module Publishing
  # The legacy's `publish_future_post` cron event (wp-includes/post.php:5482,
  # `check_and_publish_future_post()`), armed by `_future_post_hook()` on every
  # transition into `future`.
  #
  # AD-06: the legacy stored that event inside the `cron` option — the same autoloaded
  # table the 150 KB heuristic could silently de-autoload (BR-OPT-06, F-CRON-03). Here
  # it is a job in a real queue, and the model can ALSO answer "what is due?" with a
  # query (Publishing::Post.due_for_publication), so a lost job cannot lose a
  # publication: whichever discovers the record first publishes it, and the other finds
  # nothing to do.
  #
  # BR-MIGRATE-038 (BR-POST-11): the legacy clears the event on ANY status transition to
  # guard against a future -> draft bounce. A queued job cannot be recalled from every
  # adapter, so the guard lives where it cannot be forgotten: `publish_due!` refuses to
  # act on a record that is no longer scheduled. A stale job is a no-op, not a bounce.
  class PublishScheduledJob < ApplicationJob
    queue_as :default

    def perform(post_id)
      Publishing::Post.find_by(id: post_id)&.publish_due!
    end
  end
end
