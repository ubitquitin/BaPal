# BA Pal

**BA Pal** is a community-driven Lua utility for **Barbarian Assault (RuneScape 3)**, built using [PrettyUI](https://prettyui.j3.gg/). The goal is to make wave tracking, team information, and useful Barbarian Assault timers accessible in one compact in-game window.

> **Status:** Early development / experimental. The interface and data integrations are works in progress, and behavior has not yet been fully tested in Barbarian Assault.

## Planned features

- **Wave Splits:** A table of wave times for waves 1–9, with normal/hard mode selection.
- **Wave Tick:** A repeating 0–9 counter driven by server-logic events.
- **Team overview:** Current role, role points, and teammate information.
- **Future analytics:** Wave performance, call history, and other Barbarian Assault metrics.

## Getting started

1. Set up a Lua scripting environment compatible with the RuneScape client API.
2. Install or make available [PrettyUI](https://prettyui.j3.gg/#installation).
3. Load the project's Lua script using your supported scripting workflow.
4. Test cautiously: some APIs and game-state variables still need verification.

The script currently relies on `Event.ServerLogic` and several varplayer IDs. The exact installation and loading procedure may depend on your scripting environment.

## Relevant game variables

| Varplayer ID | Purpose |
| --- | --- |
| `4689` | Barbarian Assault normal/hard wave flags (bitfield) |
| `4690` | `BARBASSAULT_ROUNDTIME` |
| `1494` | Current player role |
| `1495`–`1498` | Attacker, Defender, Collector, and Healer points |
| `1499`–`1502` | Teammate player UIDs |

**Important:** The precise timer units, flag-transition semantics, and UID-to-player-name mapping still need to be confirmed in-game. The supplied flag list also lacks a normal-mode wave 1 flag.

## TODO

### Core functionality

- [ ] Hook up **normal/hard mode detection** and accurate **wave times** using varplayer `4690` (`BARBASSAULT_ROUNDTIME`), and/or chat messages or wave-number variables.
  - [ ] Determine whether round time resets each wave or accumulates across waves.
  - [ ] Confirm whether varplayer `4689` flags indicate wave completion or another state.
  - [ ] Handle the missing normal-mode wave 1 flag.
  - [ ] Format and persist splits across wave transitions.
- [ ] Resolve teammate player UIDs (`1499`–`1502`) to **player names** instead of displaying raw IDs.
  - [ ] Test whether UIDs can help dynamically identify **quickstart leavers**, including who will spawn early versus late.
- [ ] Test all functionality in Barbarian Assault once cheats work.
  - [ ] Check event subscriptions, counter synchronization, and window cleanup.
  - [ ] Validate role/points values and teammate changes.
  - [ ] Check behavior when joining late, restarting, or leaving a wave.

### Ideas and enhancements

*Contributions and new ideas are welcome. Feel free to edit this file and add your own!*

- [ ] **Automatic data tracking**
  - [ ] Wave times grouped by role and wave number.
  - [ ] Call-change history.
  - [ ] Typical number of food items dropped as Defender (potentially count ground entities).
  - [ ] Save run summaries for later review.
- [ ] **King spawn timer.**
- [ ] **Call-change timer** showing when the next call change is expected.
- [ ] Optional per-role views and useful in-game alerts.

## Contributing

Issues, feature requests, documentation fixes, and pull requests are welcome.

1. Fork the repository.
2. Create a branch: `git checkout -b feature/your-change`.
3. Make and test your changes where possible.
4. Commit your work and open a pull request explaining what changed and how it was tested.

For game-state-dependent changes, please include observed varplayer values or event behavior when possible. Avoid treating unverified client API assumptions as established behavior.

## Resources

- [PrettyUI documentation](https://prettyui.j3.gg/#installation)
- [RuneScape client API documentation](https://rs3api.j3.gg/)

