# Changelog

## 1.0.1

Fixes from a review of 1.0.0. Works together with 1.0.0 in the same group.

- Group messages are only accepted from people in your party or raid. Before, anyone could send a suggestion or proposal box.
- A made-up totem code in a suggestion can no longer put a non-totem spell on a bar icon.
- Accept / Decline boxes: at most six wait their turn, a box that has only just appeared can't be accepted by a stray double-click, and a proposal that was replaced or ran out is no longer asked about or applied.
- Accepting a proposal changes only the totems the box showed, not ones you changed in the meantime.
- Sort it out: the count no longer waits for shamans who left the group, and you are told when your proposal runs out of time.
- Someone asking for your plan over and over can no longer hold back your replies.
- No missing-totem warning while you are dead, or for a totem slot the game hides before anything has been seen in it.
- Timers are cleared after a loading screen or a death instead of counting on in hidden slots.
- Dropping Fire Nova, Stoneclaw, Mana Tide, Earthbind or Grounding no longer makes it your plan.
- The yellow "about to run out" pulse is only for totems that last longer than 15 seconds.
- The orange `x2` is skipped when the other shaman is far away.
- Low-rank Searing Totem uses its own duration when the game hides the slot.
- The tooltip says what left-click really does when you change the plan in combat (the change applies after combat).
- Right-clicking an icon again closes its menu; the tooltip no longer covers the menu.
- `/totems` says whether the bar is now shown or hidden; the welcome line points to `/totems help`.
- A non-shaman announcing in a raid gets the party number on each line.
- Clearer wording in the README, help and tooltips.

## 1.0.0

First release.

- Totem bar: four small icons (earth, fire, water, air) with the time left on each, faded while nothing needs attention.
- Pick the totem to keep up per element (right-click); left-click drops it.
- Warnings: planned totem missing, totem about to run out, a different totem down than planned.
- Group: warns when another shaman in your party has the same totem down, or plans the same one.
- Group plan window: every shaman's totems, doubles outlined in red, works for shamans without the addon too.
- Suggest a totem to another shaman (Accept / Decline), or "Sort it out" to propose a plan with no doubles that each shaman accepts.
- Announce the plan in party or raid chat.
- `/totems demo` to try the group features alone.
