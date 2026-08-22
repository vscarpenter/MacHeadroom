import { handoffOutcome, tokenFromPath } from "/direct/lib/claim-core.mjs";

const MAX_PAGE_DOWNLOADS = 3;

const states = {
  exchanging: document.getElementById("state-exchanging"),
  ready: document.getElementById("state-ready"),
  expired: document.getElementById("state-expired"),
};

function show(name) {
  for (const [key, element] of Object.entries(states)) {
    element.hidden = key !== name;
  }
}

async function redeem(token) {
  const response = await fetch("/direct/api/handoff", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ token }),
  });
  const payload = await response.json().catch(() => null);
  return handoffOutcome(response.status, payload);
}

async function run() {
  const token = tokenFromPath(location.pathname);
  if (!token) {
    show("expired");
    return;
  }

  let downloads = 0;
  const start = async () => {
    const outcome = await redeem(token).catch(() => ({ kind: "expired" }));
    if (outcome.kind !== "ready") {
      show("expired");
      return;
    }
    document.getElementById("release-version").textContent = outcome.version;
    document.getElementById("release-sha256").textContent = outcome.sha256;
    show("ready");
    downloads += 1;
    location.href = outcome.downloadURL;
  };

  document.getElementById("retry-download").addEventListener("click", () => {
    if (downloads < MAX_PAGE_DOWNLOADS) {
      start();
    } else {
      show("expired");
    }
  });

  await start();
}

run();
