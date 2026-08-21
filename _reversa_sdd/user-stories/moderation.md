# User Stories — Comment moderation

> Derived from `comments`, `users-roles-capabilities`, `kses-security`.
> Confidence: 🟢 CONFIRMED · 🟡 INFERRED

---

## US-MOD-01 — A visitor submits a comment

```gherkin
Given comments are open on the post
When a visitor submits a comment
Then a duplicate check runs first                                     # BR-CMT-01
And a flood check runs second                                         # BR-CMT-04
And an approval decision runs third                                   # BR-CMT-05…09
And a disallowed-list check OVERRIDES that decision                   # BR-CMT-10

Given the identical comment already exists on the same post and parent
When it is submitted again
Then the request is rejected with HTTP 409                            # BR-CMT-01

Given the same comment was previously TRASHED
When it is submitted again
Then it is ACCEPTED — trashed comments are excluded from the check    # BR-CMT-01
```

---

## US-MOD-02 — Flood protection

```gherkin
Given a visitor submits many comments in quick succession
When each is submitted
Then core queries for their last comment within the hour              # BR-CMT-03
And asks the comment_flood_filter whether that constitutes flooding
And the filter's DEFAULT ANSWER IS FALSE                              # BR-CMT-04
And every comment is therefore ACCEPTED                               # F-CMT-01 ⚠️

Given a rate-limiting plugin is installed
When it returns true from comment_flood_filter
Then HTTP 429 is returned
```

⚠️ **Core ships no working rate limit.** The feature reads as protection and provides none. 🟢

---

## US-MOD-03 — Moderation rules

```gherkin
Given the option comment_moderation is '1'
When any comment is submitted
Then it is HELD, and no other moderation rule is evaluated            # BR-CMT-06

Given comment_max_links is 2
When a comment contains 2 or more <a href> occurrences
Then it is held                                                       # BR-CMT-07

Given moderation_keys contains 'press'
When a comment mentions "WordPress"
Then it is HELD — keywords match as SUBSTRINGS                        # BR-CMT-08 ⚠️
And the match is tested against author, email, url, content, IP AND user agent

Given comment_previously_approved is '1'
When a first-time commenter posts
Then it is held until they have one approved comment                  # BR-CMT-09
```

---

## US-MOD-04 — Author and moderator exemption

```gherkin
Given I am the author of the post
When I comment on my own post
Then my comment is approved with NO moderation checks                 # BR-CMT-05

Given I hold moderate_comments
When I comment anywhere
Then my comment is approved with NO moderation checks                 # BR-CMT-05

Given my comment contains a disallowed-list word
When it is submitted
Then it is STILL trashed or marked spam                               # BR-CMT-10 ⚠️
```

🟢 The exemption bypasses the four moderation rules but **not** the disallowed list.

---

## US-MOD-05 — Trash versus spam

```gherkin
Given a comment matches the disallowed list
And EMPTY_TRASH_DAYS is truthy
Then the comment status becomes 'trash'                               # BR-CMT-10

Given the same comment
And EMPTY_TRASH_DAYS is 0 or undefined
Then the comment status becomes 'spam'                                # BR-CMT-10 ⚠️
```

🟢 Disabling the trash feature silently changes spam handling — two unrelated settings coupled.
