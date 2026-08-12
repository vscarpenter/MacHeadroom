# System Headroom App Review rename

## Context

Apple rejected the previously submitted 1.0 (10) build under Guideline 5.2.5
because its app name uses the Apple trademark “Mac” in a product name. The
reviewer did not cite the icon, screenshots, functionality, sandbox behavior,
or binary quality.

## Approved product identity

- App Store name: **System Headroom**
- Installed application display name: **System Headroom**
- Existing bundle identifier: `com.vinnycarpenter.MacHeadroom` (unchanged for
  App Store update compatibility)
- Project, target, module, and source names: `SystemHeadroom`

## Required changes

1. Change `CFBundleDisplayName`, `CFBundleName`, and the built `.app` filename
   through the shared `APP_DISPLAY_NAME` setting.
2. Update build/test paths and the Direct-build verifier for the renamed app
   bundle.
3. Replace all hard-coded customer-facing product labels with
   “System Headroom.”
4. Update identity tests before implementation and retain the existing stable
   bundle identifier.
5. Upload a new build and update App Store Connect metadata and review notes.
6. Reply to App Review with the exact remediation and resubmit.

## Acceptance criteria

- The app bundle and executable are named `System Headroom`.
- `CFBundleDisplayName` and `CFBundleName` are `System Headroom`.
- `CFBundleIdentifier` remains `com.vinnycarpenter.MacHeadroom`.
- The full test suite passes with no skipped or failed tests.
- App Store Connect shows the new name and a newly uploaded build.
- The review response states that the trademark was removed from the product
  name and the bundle identifier was preserved.
