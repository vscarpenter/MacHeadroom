// Pure logic for the one-time claim page. Kept framework-free and testable
// under node --test; the page script only wires DOM and fetch around it.

const CLAIM_PATH_PATTERN =
  /^\/direct\/claim\/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\/?$/;

export function tokenFromPath(pathname) {
  const match = CLAIM_PATH_PATTERN.exec(pathname);
  return match ? match[1] : null;
}

export function handoffOutcome(status, payload) {
  if (
    status === 200 &&
    payload &&
    typeof payload.downloadURL === "string" &&
    payload.downloadURL.startsWith("https://") &&
    typeof payload.version === "string" &&
    typeof payload.sha256 === "string"
  ) {
    return {
      kind: "ready",
      downloadURL: payload.downloadURL,
      version: payload.version,
      sha256: payload.sha256,
    };
  }
  return { kind: "expired" };
}
