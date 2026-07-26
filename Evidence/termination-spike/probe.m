#import <AppKit/AppKit.h>
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

// Sandbox termination probe. Modes:
//   sig0 <pid>     kill(pid, 0) permission check, no signal delivered
//   sigterm <pid>  kill(pid, SIGTERM)
//   sigkill <pid>  kill(pid, SIGKILL)
//   nsterm <pid>   [NSRunningApplication terminate]
//   nsforce <pid>  [NSRunningApplication forceTerminate]
// Every run first proves whether the sandbox is active by trying to read
// another app's preferences file, which the seatbelt denies with EPERM.

static void report(const char *label, int rc) {
  printf("%s: rc=%d errno=%d (%s)\n", label, rc, rc == 0 ? 0 : errno,
         rc == 0 ? "ok" : strerror(errno));
}

int main(int argc, char **argv) {
  if (argc < 3) {
    fprintf(stderr, "usage: %s <mode> <pid>\n", argv[0]);
    return 2;
  }
  const char *mode = argv[1];
  pid_t pid = (pid_t)atoi(argv[2]);

  // When launched as a .app via `open`, stdio goes nowhere. Mirror all
  // output into $HOME/probe-out.txt ($HOME is the container for a
  // sandboxed app), readable from outside afterward.
  const char *home = getenv("HOME");
  if (home) {
    char outpath[1024];
    snprintf(outpath, sizeof(outpath), "%s/probe-out.txt", home);
    int ofd = open(outpath, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (ofd >= 0) {
      dup2(ofd, 1);
      dup2(ofd, 2);
    }
  }

  const char *canary =
      "/Users/vinnycarpenter/Library/Preferences/com.apple.finder.plist";
  int fd = open(canary, O_RDONLY);
  printf("sandbox-active-check: open(finder plist) %s (errno=%d %s)\n",
         fd >= 0 ? "ALLOWED -> NOT sandboxed" : "DENIED -> sandboxed",
         fd >= 0 ? 0 : errno, fd >= 0 ? "" : strerror(errno));
  if (fd >= 0) close(fd);

  if (!strcmp(mode, "sig0")) {
    errno = 0;
    report("kill(pid, 0)", kill(pid, 0));
  } else if (!strcmp(mode, "sigterm")) {
    errno = 0;
    report("kill(pid, SIGTERM)", kill(pid, SIGTERM));
  } else if (!strcmp(mode, "sigkill")) {
    errno = 0;
    report("kill(pid, SIGKILL)", kill(pid, SIGKILL));
  } else if (!strcmp(mode, "nsterm") || !strcmp(mode, "nsforce")) {
    NSRunningApplication *app =
        [NSRunningApplication runningApplicationWithProcessIdentifier:pid];
    if (!app) {
      printf("%s: no NSRunningApplication for pid %d\n", mode, pid);
      return 3;
    }
    BOOL asked = !strcmp(mode, "nsterm") ? [app terminate] : [app forceTerminate];
    printf("%s: request returned %s\n", mode, asked ? "YES" : "NO");
    for (int i = 0; i < 30 && !app.terminated; i++) {
      [[NSRunLoop currentRunLoop]
          runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    }
    printf("%s: terminated=%s after wait\n", mode,
           app.terminated ? "YES" : "NO");
  } else if (!strcmp(mode, "aecheck")) {
    // Probe the Apple-events quit path WITHOUT prompting the user:
    // askUserIfNeeded=false. -1744 means "viable, would ask consent";
    // -1743 means hard-denied (e.g. sandbox without the automation
    // entitlement); 0 means already granted.
    AEAddressDesc target;
    OSStatus err = AECreateDesc(typeKernelProcessID, &pid, sizeof(pid), &target);
    if (err != noErr) {
      printf("aecheck: AECreateDesc failed %d\n", (int)err);
      return 3;
    }
    OSStatus perm = AEDeterminePermissionToAutomateTarget(
        &target, kCoreEventClass, kAEQuitApplication, false);
    AEDisposeDesc(&target);
    const char *meaning = perm == 0 ? "granted"
        : perm == -1744              ? "WOULD PROMPT (path viable)"
        : perm == -1743              ? "NOT PERMITTED (hard deny)"
        : perm == -600               ? "procNotFound"
                                     : "other";
    printf("aecheck: AEDeterminePermissionToAutomateTarget=%d (%s)\n",
           (int)perm, meaning);
  } else if (!strcmp(mode, "aecheckbid")) {
    // Same permission probe, but addressing the target by bundle id —
    // the addressing mode sandboxed senders are expected to use.
    const char *bid = argv[2];
    AEAddressDesc target;
    OSStatus err = AECreateDesc(typeApplicationBundleID, bid,
                                (Size)strlen(bid), &target);
    if (err != noErr) {
      printf("aecheckbid: AECreateDesc failed %d\n", (int)err);
      return 3;
    }
    OSStatus perm = AEDeterminePermissionToAutomateTarget(
        &target, kCoreEventClass, kAEQuitApplication, false);
    AEDisposeDesc(&target);
    const char *meaning = perm == 0 ? "granted"
        : perm == -1744              ? "WOULD PROMPT (path viable)"
        : perm == -1743              ? "NOT PERMITTED (hard deny)"
        : perm == -600               ? "procNotFound"
                                     : "other";
    printf("aecheckbid(%s): AEDeterminePermissionToAutomateTarget=%d (%s)\n",
           bid, (int)perm, meaning);
  } else {
    fprintf(stderr, "unknown mode %s\n", mode);
    return 2;
  }
  return 0;
}
