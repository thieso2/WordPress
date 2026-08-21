# Spec Examples: Good vs. Bad

These examples use the "Email Notifications" feature to illustrate the difference.

---

## ❌ Bad Spec — Score: 32/100

```markdown
# Spec: Notifications

## What we're going to do
Implement email notifications for users when something important happens.

## Requirements
- The system must send emails
- The emails must look nice
- The user must be able to turn notifications off
- It must be fast

## Technical notes
Use SendGrid or SES. Maybe an SQS queue.
```

### Why it is bad:

| Problem | Impact |
|---------|--------|
| "when something important happens" — what counts as important? | The dev implements whatever seems right, not what the business wants |
| "the emails must look nice" — untestable | No acceptance criterion is possible |
| "it must be fast" — no number | Bug: the email takes 5 min and the dev thinks that's fine |
| No non-goals | Scope creep: "what about SMS? what about push notifications?" |
| No edge cases | What happens if the email bounces? If the user turned it off? |
| Mixes the spec with a technical decision (SendGrid/SES/SQS) | Needlessly couples the "what" to the "how" |
| No requirement IDs | Impossible to trace which requirement a PR implemented |

---

## ✅ Good Spec — Score: 87/100

```markdown
# Spec: Email Notifications — Account Activity

**Version:** 1.0 | **Status:** Approved | **Date:** 2025-01-15

## 1. Summary
Send transactional email notifications to users when relevant account events
occur, with granular control over notification preferences.

## 2. Context and Motivation
**Problem:** Users miss important actions (e.g. a new comment, a processed payment)
because they only find out when they open the app. The result: late engagement and abandoned tasks.
**Evidence:** 68% of inactive users cited "I didn't know something was waiting for me"
in the Dec/2024 churn survey.
**Why now:** The email platform is contracted (SendGrid); the integration is feasible in 1 sprint.

## 3. Goals
- [ ] G-01: Users receive the email in < 2 min after the triggering event
- [ ] G-02: Open rate ≥ 25% (benchmark: 21% for the sector)
- [ ] G-03: 100% of users can turn notifications off in ≤ 3 clicks

## 4. Non-Goals
- NG-01: Push notifications (mobile) — a future version
- NG-02: SMS notifications — out of the 2025 roadmap
- NG-03: Marketing emails / newsletter — the Growth team's scope
- NG-04: Support for multiple email addresses per user

## 5. Users
**Primary:** A user with an active account, on any plan.
**Current journey:** The user has to open the app to see whether anything new happened.
**Future journey:** The user receives an email summarizing the event with a direct link to the action.

## 6. Functional Requirements

| ID | Requirement | Priority | Acceptance criterion |
|----|-------------|----------|----------------------|
| FR-01 | The system must send an email when a comment is added to one of the user's items | Must | The email arrives in < 2 min in 95% of cases (tested with 100 sends) |
| FR-02 | The system must send an email when a payment is processed (success or failure) | Must | The email arrives in < 2 min; it includes the amount, date and status |
| FR-03 | The user must be able to turn each notification type off individually in Settings > Notifications | Must | The toggle persists across logout/login; an email of a disabled type is not sent |
| FR-04 | The system must include a "cancel all notifications" link in the footer of every email | Must | The link works without logging in; it redirects to a confirmation page |
| FR-05 | The system must group notifications of the same type into a daily digest when there are > 5 events in 1h | Should | The user receives 1 email listing the 5+ events, not 5+ separate emails |

### Main flow (FR-01)
1. User B comments on User A's item X
2. The system detects the `comment.created` event
3. The system checks whether User A has FR-01 enabled (default: enabled)
4. The system sends User A an email with: the commenter's name, an excerpt of the comment (max. 200 chars), and a direct link to the item
5. Result: User A receives the email in < 2 min

## 7. Non-Functional Requirements
| ID | Requirement | Target |
|----|-------------|--------|
| NFR-01 | Send latency | P95 < 2 min after the event |
| NFR-02 | Delivery rate | ≥ 98% (excluding permanent bounces) |
| NFR-03 | Security | Unsubscribe links with a unique, signed token |

## 11. Edge Cases

| ID | Scenario | Trigger | Behavior |
|----|----------|---------|----------|
| EC-01 | Invalid email/permanent bounce | SendGrid returns a hard bounce | Disable sends to that address; notify the user in-app |
| EC-02 | The user turned notifications off | `user.notifications.comments = false` | Do not send; do not log an error |
| EC-03 | SendGrid unavailable | A timeout or a 5xx error | Retry with backoff: 1 min, 5 min, 30 min. After 3 failures: log it and alert the team |
| EC-04 | The user deleted their account before the send | The user ID is not found in the queue | Discard silently; log it for auditing |
| EC-05 | The same event fires twice | A duplication bug | Deduplicate by event_id with a 1h TTL |

## 14. Open Questions
| # | Question | Impact | Deadline |
|---|----------|--------|----------|
| OQ-01 | ⚠️ OPEN: Daily digest (FR-05) — what time is it sent? The user's timezone or UTC? | Medium | Jan 20 |
```

### Why it is good:

| Strength | Benefit |
|----------|---------|
| Every requirement has an ID, a priority and an acceptance criterion | QA writes tests straight from the table |
| Explicit non-goals (4 items) | The team knows exactly what to turn down |
| Edge cases cover external failures | The dev implements retries without having to ask |
| Numeric metrics (< 2 min, ≥ 25%) | Success is verifiable |
| An Open Question flagged with `⚠️ OPEN:` | The ambiguity is visible, not silent |
| A step-by-step main flow | An LLM implements it without assumptions |

---

## 🔶 Mediocre Spec — Score: 63/100

```markdown
# Spec: Login with Google

## Goal
Let users log in using their Google account.

## Requirements
- FR-01: Add a "Sign in with Google" button on the login screen
- FR-02: The user must be redirected to Google's OAuth
- FR-03: After authentication, create the user's session
- FR-04: If the email already exists in the system, log into the existing account
- FR-05: If the email does not exist, create a new account automatically

## Out of scope
- Login with Facebook/Apple for now

## Edge Cases
- What if the user cancels the OAuth flow?
- What if Google is down?
```

### What is good:
- Numbered requirements ✅
- Non-goals present ✅
- Edge cases identified (but with no answer) ⚠️

### What is missing (-37 points):
- Edge cases with no defined behavior — "what if?" with no answer (-10)
- No acceptance criteria on the requirements (-7)
- No security section (OAuth data, tokens) (-8)
- No success metrics (-7)
- FR-03 "create the session" — for how long? With what data? (-5)
