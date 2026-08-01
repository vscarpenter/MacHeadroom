// Ports-view sandbox spike probe.
//
// Measures, under the App Sandbox (and unsandboxed as control), the two
// candidate paths for mapping listening ports to owning processes:
//
//   Path A (lsof-style, per-process fd walk):
//     proc_pidinfo(pid, PROC_PIDLISTFDS)  ->  proc_pidfdinfo(pid, fd,
//     PROC_PIDFDSOCKETINFO) for every socket fd, extracting TCP LISTEN
//     state and bound local ports.
//
//   Path B (netstat-style, global sysctl):
//     sysctlbyname("net.inet.tcp.pcblist_n") / ("net.inet.udp.pcblist_n").
//     Layout structs are not in the public SDK, so instead of parsing we
//     scan the raw buffer for the ground-truth listener's port bytes
//     (big-endian) and its pid bytes (little-endian int32) to learn
//     whether the data (a) is returned at all and (b) carries pids.
//
// Usage: probe <ground-truth-pid> <ground-truth-port>
// Every run first proves whether the sandbox is active by trying to read
// another app's preferences file (EPERM when sandboxed).

#include <errno.h>
#include <fcntl.h>
#include <libproc.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/proc_info.h>
#include <sys/sysctl.h>
#include <arpa/inet.h>
#include <unistd.h>

static void sandbox_proof(void) {
  char path[1024];
  snprintf(path, sizeof(path), "%s/Library/Preferences/com.apple.finder.plist",
           getenv("HOME") ? getenv("HOME") : "");
  errno = 0;
  int fd = open(path, O_RDONLY);
  if (fd >= 0) {
    printf("sandbox-proof: finder plist OPENED (unsandboxed)\n");
    close(fd);
  } else {
    printf("sandbox-proof: finder plist DENIED errno=%d (%s)\n", errno,
           strerror(errno));
  }
}

struct class_counts {
  int attempts, ok, eperm, esrch, other;
};

static void count(struct class_counts *c, int rc_bytes) {
  c->attempts++;
  if (rc_bytes > 0) {
    c->ok++;
  } else if (errno == EPERM) {
    c->eperm++;
  } else if (errno == ESRCH) {
    c->esrch++;
  } else {
    c->other++;
  }
}

static void path_a(pid_t truth_pid, int truth_port) {
  printf("\n== Path A: proc_pidinfo(PROC_PIDLISTFDS) fd walk ==\n");

  // Enumerate all pids the way the shipping app does.
  int mib[3] = {CTL_KERN, KERN_PROC, KERN_PROC_ALL};
  size_t len = 0;
  if (sysctl(mib, 3, NULL, &len, NULL, 0) != 0) {
    printf("KERN_PROC_ALL size query FAILED errno=%d\n", errno);
    return;
  }
  len += len / 4;
  struct kinfo_proc *procs = malloc(len);
  if (sysctl(mib, 3, procs, &len, NULL, 0) != 0) {
    printf("KERN_PROC_ALL fetch FAILED errno=%d\n", errno);
    free(procs);
    return;
  }
  int nprocs = (int)(len / sizeof(struct kinfo_proc));
  uid_t me = geteuid();
  pid_t self = getpid();
  printf("KERN_PROC_ALL: %d processes, euid=%d self=%d\n", nprocs, me, self);

  struct class_counts self_c = {0}, same_user = {0}, root_c = {0},
                      other_user = {0};
  int listeners_found = 0, listen_pids = 0;
  int truth_seen = 0;
  int truth_listfds_rc = -2, truth_listfds_errno = 0;

  for (int i = 0; i < nprocs; i++) {
    pid_t pid = procs[i].kp_proc.p_pid;
    uid_t uid = procs[i].kp_eproc.e_ucred.cr_uid;
    if (pid <= 0) continue;

    errno = 0;
    int bytes = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, NULL, 0);
    struct class_counts *bucket =
        (pid == self) ? &self_c
        : (uid == me) ? &same_user
        : (uid == 0)  ? &root_c
                      : &other_user;
    count(bucket, bytes);

    if (pid == truth_pid) {
      truth_listfds_rc = bytes;
      truth_listfds_errno = errno;
    }
    if (bytes <= 0) continue;

    int cap = bytes + 32 * (int)sizeof(struct proc_fdinfo);
    struct proc_fdinfo *fds = malloc((size_t)cap);
    int got = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, fds, cap);
    int nfds = got > 0 ? got / (int)sizeof(struct proc_fdinfo) : 0;
    int pid_listens = 0;
    for (int f = 0; f < nfds; f++) {
      if (fds[f].proc_fdtype != PROX_FDTYPE_SOCKET) continue;
      struct socket_fdinfo si;
      errno = 0;
      int r = proc_pidfdinfo(pid, fds[f].proc_fd, PROC_PIDFDSOCKETINFO, &si,
                             sizeof(si));
      if (r != sizeof(si)) continue;
      if (si.psi.soi_kind == SOCKINFO_TCP &&
          si.psi.soi_proto.pri_tcp.tcpsi_state == TSI_S_LISTEN) {
        int port = ntohs((uint16_t)si.psi.soi_proto.pri_tcp.tcpsi_ini.insi_lport);
        listeners_found++;
        pid_listens++;
        if (pid == truth_pid && port == truth_port) truth_seen = 1;
      }
    }
    if (pid_listens > 0) listen_pids++;
    free(fds);
  }
  free(procs);

  printf("LISTFDS self:       ok=%d eperm=%d other=%d of %d\n", self_c.ok,
         self_c.eperm, self_c.other + self_c.esrch, self_c.attempts);
  printf("LISTFDS same-user:  ok=%d eperm=%d esrch=%d other=%d of %d\n",
         same_user.ok, same_user.eperm, same_user.esrch, same_user.other,
         same_user.attempts);
  printf("LISTFDS root:       ok=%d eperm=%d esrch=%d other=%d of %d\n",
         root_c.ok, root_c.eperm, root_c.esrch, root_c.other, root_c.attempts);
  printf("LISTFDS other-user: ok=%d eperm=%d esrch=%d other=%d of %d\n",
         other_user.ok, other_user.eperm, other_user.esrch, other_user.other,
         other_user.attempts);
  printf("TCP LISTEN sockets discovered: %d across %d pids\n", listeners_found,
         listen_pids);
  printf("ground truth pid %d LISTFDS rc=%d errno=%d; port %d %s\n", truth_pid,
         truth_listfds_rc, truth_listfds_errno, truth_port,
         truth_seen ? "FOUND with owner" : "NOT FOUND");
}

static void scan(const unsigned char *buf, size_t len, pid_t truth_pid,
                 int truth_port) {
  unsigned char portbe[2] = {(unsigned char)((truth_port >> 8) & 0xff),
                             (unsigned char)(truth_port & 0xff)};
  int32_t pid32 = (int32_t)truth_pid;
  unsigned char pidle[4];
  memcpy(pidle, &pid32, 4);

  int port_hits = 0, pid_hits = 0, near = 0;
  long last_port_at = -1;
  for (size_t i = 0; i + 4 <= len; i++) {
    if (i + 2 <= len && buf[i] == portbe[0] && buf[i + 1] == portbe[1]) {
      port_hits++;
      last_port_at = (long)i;
    }
    if (memcmp(buf + i, pidle, 4) == 0) {
      pid_hits++;
      if (last_port_at >= 0 && (long)i - last_port_at < 512) near++;
    }
  }
  printf("  scan: port-byte hits=%d pid-byte hits=%d pid-within-512B-after-port=%d\n",
         port_hits, pid_hits, near);
}

static void path_b(pid_t truth_pid, int truth_port) {
  printf("\n== Path B: sysctl pcblist_n (netstat -anv path) ==\n");
  const char *names[] = {"net.inet.tcp.pcblist_n", "net.inet.udp.pcblist_n"};
  for (int i = 0; i < 2; i++) {
    size_t len = 0;
    errno = 0;
    int rc = sysctlbyname(names[i], NULL, &len, NULL, 0);
    printf("%s size query: rc=%d errno=%d len=%zu\n", names[i], rc, errno, len);
    if (rc != 0 || len == 0) continue;
    len += len / 4;
    unsigned char *buf = malloc(len);
    errno = 0;
    rc = sysctlbyname(names[i], buf, &len, NULL, 0);
    printf("%s fetch: rc=%d errno=%d bytes=%zu\n", names[i], rc, errno, len);
    if (rc == 0 && i == 0) scan(buf, len, truth_pid, truth_port);
    free(buf);
  }
}

int main(int argc, char **argv) {
  if (argc < 3) {
    fprintf(stderr, "usage: %s <ground-truth-pid> <ground-truth-port>\n",
            argv[0]);
    return 2;
  }
  pid_t truth_pid = (pid_t)atoi(argv[1]);
  int truth_port = atoi(argv[2]);
  sandbox_proof();
  path_a(truth_pid, truth_port);
  path_b(truth_pid, truth_port);
  printf("\ndone\n");
  return 0;
}
