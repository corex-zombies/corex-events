# corex-events

> Six built-in dynamic world events — supply drops, outbreaks, convoys, airdrops, rescues, extractions.

Part of the [COREX Framework](https://github.com/corex-zombies).

## Install

Drop the `corex-events` folder into:
```
server-data/resources/[corex]/corex-events/
```

The manifest requires Core, Loot, and Zombies:
```cfg
ensure corex-core
ensure corex-loot
ensure corex-zombies
ensure corex-events
```

The resource does not name an inventory provider. Reward/item delivery goes
through CoreX's inventory boundary, so replacing or stopping a particular
inventory must not become a hard manifest dependency here.

## Current behavior and limits

- Six event implementations are loaded by the manifest: supply drop, zombie
  outbreak, convoy ambush, airdrop crash, survivor rescue, and extraction.
- Event teleport requests validate coordinates and keep the player frozen until
  destination ground and collision are available. If the destination cannot be
  loaded, the code returns the player to the original position. If collision at
  the origin also cannot be restored, the player stays frozen for safety and
  the diagnostic instructs them to reconnect.
- Those teleport protections are present in the local code and covered by
  focused tests, but they are not a claim that connected gameplay acceptance
  for this release candidate has completed.

## Update

Use the matching reviewed COREX resource set and merge configuration changes.
Do not mix this candidate with older Loot/Zombies implementations.

## Docs
📖 <https://corex-zombies.gitbook.io/corex-docs/reference/world-events>

## Community
💬 <https://discord.gg/G95rtnb9sg>

## License
Released under the [MIT License](LICENSE).
