# Process glossary design

Date: July 24, 2026. Approved by Vinny (row style: friendly name +
technical subtitle + hover explanation).

## Problem

The top-10 lists surface macOS daemons most people cannot decode:
`biomesyncd`, `suggestd`, `corespotlightd`. These are exactly the rows
that alarm users when they top the CPU list, and they render with a
generic gear icon and a cryptic name.

## Approach

A curated, offline glossary in the app — no network, no third-party
data, per the brief's hard constraints.

- `UI/ProcessGlossary.swift`: a pure lookup table mapping technical
  process names to an `Entry { friendlyName, blurb }`, plus
  `entry(for: AppGroup)`.
- The glossary applies only to groups with no real app identity
  (`bundleIdentifier == nil`). Groups backed by `NSWorkspace` metadata
  (Finder, Control Center) already have friendly names and icons.
- Lookup keys are truncated to 16 characters because process names come
  from `kinfo_proc.p_comm`, which is capped at `MAXCOMLEN` (16). Long
  canonical names like `searchpartyuseragent` must match their
  truncated on-the-wire form.

## Presentation

In `GroupRowView`, a glossary hit renders:

- the friendly name as the row title,
- the technical name beneath it in small secondary text,
- a hover tooltip (`.help`) with a one-sentence explanation,
- an accessibility label leading with the friendly name.

Rows without a glossary hit are unchanged. Child rows keep technical
names; the subtitle already bridges the two vocabularies.

## Catalog policy

Only same-user processes can appear (App Sandbox hides root and
other-user processes), so the catalog targets user-session daemons and
agents (~35 entries). Blurbs are one sentence, plain, calm, and honest —
no scare words, no marketing. Names describe function, not internals:
"Spotlight Indexing", not "metadata server".

## Testing

- Known name maps to a friendly entry with a non-empty blurb.
- Unknown names return nil.
- A canonical name longer than 16 characters matches its truncated form.
- A group with a bundle identifier never gets a glossary entry.
