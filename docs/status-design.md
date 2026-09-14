# Status design

Evidence badges use a traffic light convention as a secondary cue. Visible,
translated text always carries the meaning; icons distinguish shapes when colour
is unavailable. Use Discourse theme palette variables, with normal primary text,
rather than hardcoded traffic light colours or coloured text alone.

| Evidence | Colour family | Icon |
| --- | --- | --- |
| No significant match | Success | Circle check |
| Some concern (weak evidence or contextual concern) | Caution | Eye |
| Needs review | Caution | Warning triangle |
| Strong evidence | Danger | Circle exclamation |
| Check unavailable | Neutral | Circle question |
| Not checked | Neutral | Circle question |

Green describes the lookup, not the person's trustworthiness. Missing evidence,
provider failures and skipped checks must never produce a green result. More than
one state can share a colour: the labels retain the distinctions.

With engagement assessment, the leading badge shows the combined assessment.
The evidence panel also shows the original external reputation badge alongside
the reading adjustment. Strong external evidence remains visible when reading
changes an automatic-silence recommendation to human review.

The account dashboard and admin user list share `SpamWardenRiskScore`: a large
percentage summary and a compact list version. Percentages express the existing
0–100 rules index, not a statistically calibrated probability. The numeric bands
below set the colour in both contexts unless an account is currently exempt.
Evidence and action recommendations remain separate from the numeric band.
Unknown, skipped and legacy unscored checks show “Not scored”, never an invented
zero. The user list receives the stored score, without recalculating or looking up
the account on the provider.

An active account exemption overrides the score box colour in both views using
the theme's tertiary hover background and secondary foreground (blue and white
in the default light palette). A visible “Exempt” label carries the meaning
without colour. The saved score is preserved; no score is invented for an
unchecked account. The full dashboard explains that this is a manual override
and the score is historical. Removing the exemption restores the assessment
colour. The underlying evidence and scan history are unchanged.

The user list has a dedicated Spam Warden column. Its compact box is the link to
`/admin/users/:id/:username?spamWarden=true#spam-warden`; the registered query parameter
opens the account dashboard, and the fragment identifies the scroll target.
Discourse strips fragments before internal route transitions, so opening must
observe the router's query parameters rather than depend on `window.location.hash`.
Compact unscored boxes use grey N/A, while actual scored
zeroes remain 0%. The full dashboard spells out “Not scored”. The additional
column is included in the admin table's grid count, and absent for moderators.

A permanent grey Spam Warden heading contains a full-width native button with the
title and expand/collapse chevron. The entire header toggles the dashboard; native
button semantics support keyboard activation, with a visible focus outline and
`aria-expanded` state. Collapsing retains loaded details. The
heading remains available to reopen the dashboard. User-list links still expand
it automatically. Opening displays stored evidence without running a new check.

The dashboard groups the assessment and outcome, reading metrics, score
contributions and provider signals. Dates use Discourse's relative-date formatter
with an exact-date tooltip. Longer interpretive guidance sits in native expandable
details, while the score's non-probabilistic meaning remains visible.

Actions are a separate dimension: observed, queued for review, or silenced and
queued for review. Scan actions describe what happened at the time of the check,
not the account's current restriction status. An administrator's exception is also
displayed separately. For example, strong evidence in observe mode must still show
that no action was taken.

Use the same status component in free and Pro interfaces. Paid features may add
evidence or workflow states, but accessibility and explanations remain free.
Do not hide essential meaning in tooltips or require users to distinguish hues.

Reference: [WCAG 2.2 use of colour](https://www.w3.org/WAI/WCAG22/Understanding/use-of-color.html).

## Numeric score colours (0.1.3)

The shared dashboard and user-list score box uses numeric bands independently of
the action recommendation: 0 green (No scored concern), 1–30 yellow (Suspicious),
31–69 amber (Moderate concern), and 70–100 red (High concern). A saved score of zero
is green even when the evidence still warrants review. A zero score is not proof
that the account is safe. Exempt accounts override all numeric bands with blue and
an explicit Exempt label; unavailable scores remain grey N/A. Colour bands never
authorize moderation actions. Theme palette colours and text labels support both
light and dark themes; amber mixes the theme's yellow and red colours.
