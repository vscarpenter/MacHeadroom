# Direct edition Settings — Option A

Status: approved for implementation on August 16, 2026.

## Outcome

The App Store edition gives an eligible customer one quiet route from General
settings to a complete Direct-edition explanation in Help. Help owns the
comparison, purchase verification, progress, success, and failure states.

## Policy and release gate

The surface is fail-closed. Both the General Edition section and the Help
Direct-edition section are hidden unless all of these are true:

1. The running build is sandboxed and cannot terminate processes.
2. `DIRECT_EDITION_CLAIM_URL` resolves to a valid HTTPS endpoint.

The implementation must not populate that build setting, enable the deployed
claim service, deliver a DMG, or imply that Apple has approved the transfer
model. Those remain separate release decisions.

## General settings

Add a native `Edition` section after Appearance:

- `Current build` displays `App Store`.
- `Compare editions…` selects the existing Help tab and requests the Direct
  edition section.
- The button uses native keyboard and focus behavior and has a concise help
  description.

The section is not shown in the Direct build or while the claim endpoint is
unconfigured.

## Help

The Direct edition section explains:

- why App Store sandboxing limits physical-footprint memory and process
  controls;
- that Direct is Developer ID signed and Apple notarized;
- that Direct uses physical-footprint memory, adds Quit and Force Quit, and
  receives updates outside the App Store;
- that it installs alongside the App Store edition;
- that access is included with the App Store purchase with no additional
  payment or account.

The existing claim-state controls remain the only action in this section.
`Compare editions…` opens Help with this section first. Opening Help directly
keeps the normal task-oriented order. This avoids timing-sensitive
programmatic scrolling and adds no custom motion.

## Acceptance criteria

- An unconfigured App Store build renders exactly the current Settings and Help
  surfaces and makes no claim-service request.
- A configured App Store build shows the Edition row and Direct Help section.
- A Direct build shows neither transfer entry point.
- The deep link selects Help and places the Direct edition section first.
- All interactive elements use native SwiftUI controls with accessible names,
  keyboard behavior, visible focus, and status text during verification.
- Existing Settings and Help rendering tests remain green, with configured
  fixtures covering the new surface.
