# Spontaan: course ideas as working subsystems

Spontaan should take a person's intent through relevant possibilities, feasible
coordination, explicit participation and physical activity. The product should
reduce the work between those steps. Time spent browsing is not its objective.

This is a product synthesis, not a claim to reproduce four course syllabuses.
The available personal course context includes MAS lecture material on agents,
environment, time, situated behaviour and topology, and a team brief requiring
goal-directed, proactive, socially interacting agents. Previous study planning
also asks the Future Atlas to generate requirements. Detailed current NLP and
IR lecture materials were not available in the retrieved sources.

| Course | Product responsibility | Concrete design |
| --- | --- | --- |
| MAS | Coordinate actors with different goals, resources and authority | Separate discovery, host coordination, resource reporting and referee assistance. Each proposal states its source, expiry, prerequisites, permitted action and responsible person. Durable memory does not renew authority. |
| Knowledge / information retrieval | Retrieve useful opportunities from the activities that actually exist | Resolve vocabulary differences, rank matches, expose matching evidence and retain explicit filters. Evaluate relevance against expressed needs and feasibility, rather than clicks. |
| NLP | Translate language into a reviewable intention | Start with explainable English/Dutch hobby aliases and short phrases. Future structured requests show the interpreted activity, time, place and requirements before any consequential action. Unknown requirements remain visible. |
| Create the Future | Derive today's engineering decisions from possible lived futures | Describe an ordinary day under different ownership/resource conditions, work backwards to prerequisites and record requirements. Scenarios specify how people act and leave, as well as how they discover and join. |

## First delivered slice: explainable discovery

- `I want to play ping pong` and `Ik wil graag tafeltennis` retrieve the same
  activity aliases. Unknown hobbies remain searchable as ordinary words.
- Each remaining search term must match that same event's title, hobby or place.
  Matches in the hobby outrank incidental title mentions, then place mentions.
  Relevance ordering happens in the database before bounded pagination; existing
  start-time/ID ordering resolves equal scores.
- Explore displays the search terms and a **Why this match?** explanation. Clear
  search preserves the other filters. URLs and live refresh retain the query.
- Category, format, place, participation, capacity and personal-history scoping
  remain hard filters. Search changes no join, reservation, score or authority.
- This is a small lexical baseline with curated aliases, not embeddings, BM25,
  an LLM, an autonomous agent or a general natural-language constraint parser.
  Negation, alternatives and unsupported time/equipment words are retained as
  search terms; their constraints are not inferred or promised. No model service
  receives the query and no search history is added by this feature.

## Three futures and the requirements they expose

These are design scenarios for the fictional Commons, not predictions or
observations about a real organization.

| Possible day | What can break | Requirement and current boundary |
| --- | --- | --- |
| A shared-resource commons | A popular event consumes scarce equipment while another group waits | Show resource conflicts and release unused reservations. Non-overlap exists; fair allocation, waitlists and measured utilization remain future work. |
| A fragmented organization | A receiver disconnects or the usual organizer leaves | Carry original observation times through retries, mark stale evidence and make responsibility transferable. Durable receiver delivery exists; host succession and complete offline operation remain open. |
| A platform-controlled club | Ranking steers everyone toward profitable activities and people cannot contest decisions | Explain relevance, preserve direct filters and keep human decisions reviewable. Search explanations and score corrections exist; independent governance and complete account/data export remain open. |

Backcast from a preferred day: someone expresses an intention, sees relevant
options with their actual limitations, chooses a commitment, participates, and
releases the shared resources. Build the missing prerequisites in that order.

## Next complete slices

1. **Bounded coordination proposals (MAS):** reuse persisted readiness facts to
   propose one next action with a named responsible person, evidence and expiry.
   Recheck prerequisites when the action is invoked. Do not silently manufacture
   bookings, commitments, messages or sanctions.
2. **Structured intention preview (NLP):** make time windows, participation and
   explicit exclusions editable; show unsupported or ambiguous requirements.
   Dates need an explicit timezone. Distance needs supplied coordinates and an
   agreed location policy. Neither is inferred from a hobby theme.
3. **Scenario-to-requirement view (Create the Future):** compare resource
   scarcity, organizer absence and infrastructure outage using the same activity
   model. Keep simulated outcomes separate from physical observations.
4. **Retrieval evaluation (IR):** maintain judged needs covering aliases, unknown
   hobbies, conflicting requirements and unavailable activities. Compare this
   lexical baseline with further ranking methods before adding complexity.

Measure time from intent to a useful choice, completed participation, organizer
minutes and constraints actually satisfied. Small regression cases establish
specific behaviours; they do not demonstrate general relevance or real-world
outcomes.

## Concept references

- Manning, Raghavan and Schütze, *Introduction to Information Retrieval*,
  [query expansion](https://nlp.stanford.edu/IR-book/html/htmledition/relevance-feedback-and-query-expansion-1.html)
  and [evaluation](https://nlp.stanford.edu/IR-book/pdf/08eval.pdf).
- Eggink and Albert-de-la-Bruhèze,
  [Design Story Telling](https://ris.utwente.nl/ws/portalfiles/portal/5527773/150611_DesignStorytelling_Cumulus2015_Eggink_AlbertdelaBruheze.pdf).
  This is background for scenario-driven design, not evidence of the current
  class assignment or of completed Spontaan functionality.
