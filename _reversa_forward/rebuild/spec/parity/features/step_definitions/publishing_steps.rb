# frozen_string_literal: true

# PT-001 -- Publishing a content record. BR-MIGRATE-029..039.
#
# Inspector contract (paradigm_decision.md): "Write parity tests for derived state as
# BEHAVIOUR, not as implementation: assert that publishing with a date 90 seconds ahead
# yields a scheduled record, without asserting how the model computes it."
# Nothing below reaches for a callback, a validation name or a column default.

Given("an author with permission to publish") do
  @author = Identity::User.create!(
    login: "parity_author", email: "parity_author@example.com", nicename: "parity-author",
    password: "correct horse battery staple", display_name: "Parity Author"
  )
  @author.assign_role("author")
end

Given("an author creating a new record") do
  step "an author with permission to publish"
  @record = Publishing::Article.new(title: "Parity draft", content: "body", excerpt: "",
                                    author: @author)
end

Given("a draft whose publication instant is {int} seconds in the future") do |seconds|
  step "an author with permission to publish" unless @author
  @record = Publishing::Article.create!(
    title: "Parity draft", content: "body", excerpt: "", status: "draft", author: @author
  )
  @requested_instant = Time.current + seconds.seconds
end

Given("a record in status {string}") do |status|
  step "an author with permission to publish" unless @author
  @record = Publishing::Article.new(
    title: "Parity record", content: "body", excerpt: "", author: @author, status: status
  )
  @record.published_at = Time.current if %w[published scheduled].include?(status)
  @record.save!
end

Given("a newly created record") do
  step "an author with permission to publish" unless @author
  @record = Publishing::Article.create!(title: "Parity record", content: "b", excerpt: "",
                                        status: "draft", author: @author)
end

Given("a published record of type {string} with parent {string} and slug {string}") do |type, parent_slug, slug|
  step "an author with permission to publish" unless @author
  klass = type == "page" ? Publishing::Page : Publishing::Article
  @parent = klass.create!(title: parent_slug.titleize, slug: parent_slug, content: "", excerpt: "",
                          status: "published", published_at: 1.day.ago, author: @author)
  @record = klass.create!(title: slug.titleize, slug: slug, parent: @parent, content: "", excerpt: "",
                          status: "published", published_at: 1.day.ago, author: @author)
  @conflict_klass = klass
end

Given("the permalink structure reserves the segment {string}") do |segment|
  expect(Routing::PermalinkStructure.current.reserved_segments).to include(segment)
  @reserved_segment = segment
end

Given("a requested slug of {int} bytes that already exists") do |bytes|
  step "an author with permission to publish" unless @author
  @requested_slug = "s" * bytes
  Publishing::Article.create!(title: "Existing", slug: @requested_slug, content: "", excerpt: "",
                              status: "published", published_at: 1.day.ago, author: @author)
end

When("the author requests publication") do
  @record.publish!(at: @requested_instant)
end

When("the record is saved as a draft") do
  @record.status = "draft"
  @record.save!
end

When("a second record of type {string} with parent {string} and slug {string} is written directly to the database") do |type, _parent_slug, slug|
  # "written DIRECTLY to the database": the point of BR-MIGRATE-033 under AD-05 is that
  # the guarantee is the unique index, not a model validation. Going through the model
  # would prove only that the validation exists.
  klass = type == "page" ? Publishing::Page : Publishing::Article
  @write_error = begin
    ActiveRecord::Base.connection.execute(<<~SQL)
      INSERT INTO posts (type, parent_id, slug, title, content, excerpt, status, published_at, modified_at)
      VALUES ('#{klass.name}', #{@parent.id}, '#{slug}', 'Duplicate', '', '', 'published', now(), now())
    SQL
    nil
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::StatementInvalid => e
    e
  end
end

When("an author publishes a record whose requested slug is {string}") do |requested|
  step "an author with permission to publish" unless @author
  @record = Publishing::Article.new(title: requested, content: "", excerpt: "",
                                    status: "published", published_at: 1.minute.ago, author: @author)
  Routing::SlugAllocator.new.allocate!(@record, requested: requested)
end

When("the author publishes the record") do
  @record = Publishing::Article.new(title: "Long", content: "", excerpt: "", status: "published",
                                    published_at: 1.minute.ago, author: @author)
  Routing::SlugAllocator.new.allocate!(@record, requested: @requested_slug)
end

When("the record moves to {string}") do |status|
  case status
  when "published" then @record.publish!(at: Time.current)
  when "trashed"   then @record.trash!
  else @record.update!(status: status)
  end
end

When("the record is trashed") { @record.trash! }
When("the record is restored") { @record.restore! }

When("the record's slug is changed after publication") do
  @uuid_before = @record.guid
  @record.update!(slug: "a-different-slug")
end

Then("the record's status is {string}") do |status|
  expect(@record.reload.status).to eq(status)
end

Then("the record is visible on the public archive") do
  expect(Publishing::Article.visible).to include(@record)
end

Then("the record is not visible on the public archive") do
  expect(Publishing::Article.visible).not_to include(@record)
end

Then("the record has no slug") do
  expect(@record.reload.slug).to be_nil
end

Then("no slug uniqueness conflict is raised against any other draft") do
  # handoff.md "Six things", item 1: reproducing the legacy's NOT NULL DEFAULT '' would
  # collide every draft against every other. The partial index WHERE slug IS NOT NULL is
  # what makes the constraint expressible at all.
  expect {
    3.times { |i| Publishing::Article.create!(title: "Another draft #{i}", content: "", excerpt: "", status: "draft", author: @author) }
  }.not_to raise_error
  expect(Publishing::Article.where(slug: nil).count).to be >= 4
end

Then("the write is rejected by a uniqueness constraint") do
  expect(@write_error).to be_present
  expect(@write_error.message).to match(/unique|duplicate key/i)
end

Then("exactly one record with that slug, type and parent exists") do
  expect(@conflict_klass.where(slug: @record.slug, parent_id: @parent.id).count).to eq(1)
end

Then("the allocated slug is not {string}") do |value|
  expect(@record.reload.slug).not_to eq(value)
end

Then("the allocated slug begins with {string} followed by a numeric suffix") do |prefix|
  expect(@record.reload.slug).to match(/\A#{Regexp.escape(prefix)}-\d+\z/)
end

Then("the allocated slug is at most {int} bytes in total") do |bytes|
  expect(@record.reload.slug.bytesize).to be <= bytes
end

Then("the numeric suffix is present within those {int} bytes") do |_bytes|
  expect(@record.reload.slug).to match(/-\d+\z/)
end

# The Inspector spells the number out ("two status transitions"), so the step does too
# rather than editing the feature file to suit the implementation.
WORD_NUMBERS = { "one" => 1, "two" => 2, "three" => 3, "four" => 4 }.freeze

Then("{word} status transitions are recorded for that record") do |count|
  expected = WORD_NUMBERS.fetch(count) { Integer(count) }
  expect(@record.status_transitions.count).to eq(expected)
end

Then("the transitions are ordered draft to published, then published to trashed") do
  pairs = @record.status_transitions.order(:occurred_at, :id).pluck(:from_status, :to_status)
  expect(pairs).to eq([%w[draft published], %w[published trashed]])
end

Then("the record records both a trash instant and its prior status") do
  @record.reload
  expect(@record.trashed_at).to be_present
  expect(@record.status_before_trash).to be_present
end

Then("the record carries a UUID identifier") do
  expect(@record.reload.guid).to match(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/)
end

Then("the UUID identifier is unchanged") do
  expect(@record.reload.guid).to eq(@uuid_before)
end
