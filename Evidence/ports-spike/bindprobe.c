// Measures, under App Sandbox without network.server: (a) TCP bind+listen,
// (b) UDP bind, on wildcard and loopback; (c) exec of /usr/sbin/netstat.
#include <arpa/inet.h>
#include <errno.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

static void try_bind(const char *label, int type, const char *addr) {
  int s = socket(AF_INET, type, 0);
  if (s < 0) { printf("%s: socket() errno=%d\n", label, errno); return; }
  struct sockaddr_in sa; memset(&sa, 0, sizeof(sa));
  sa.sin_family = AF_INET; sa.sin_port = 0;
  inet_pton(AF_INET, addr, &sa.sin_addr);
  errno = 0;
  int rc = bind(s, (struct sockaddr *)&sa, sizeof(sa));
  int bind_errno = errno;
  int lrc = 0, lerrno = 0;
  if (rc == 0 && type == SOCK_STREAM) {
    errno = 0; lrc = listen(s, 1); lerrno = errno;
  }
  printf("%s: bind rc=%d errno=%d (%s)", label, rc, bind_errno,
         rc == 0 ? "ok" : strerror(bind_errno));
  if (rc == 0 && type == SOCK_STREAM)
    printf("; listen rc=%d errno=%d (%s)", lrc, lerrno,
           lrc == 0 ? "ok" : strerror(lerrno));
  printf("\n");
  close(s);
}

int main(void) {
  try_bind("tcp-wildcard", SOCK_STREAM, "0.0.0.0");
  try_bind("tcp-loopback", SOCK_STREAM, "127.0.0.1");
  try_bind("udp-wildcard", SOCK_DGRAM, "0.0.0.0");
  try_bind("udp-loopback", SOCK_DGRAM, "127.0.0.1");
  errno = 0;
  FILE *p = popen("/usr/sbin/netstat -anv -p tcp 2>&1", "r");
  if (!p) { printf("netstat: popen failed errno=%d\n", errno); return 0; }
  char line[512]; int lines = 0;
  while (fgets(line, sizeof(line), p) && lines < 4) {
    printf("netstat| %s", line); lines++;
  }
  int st = pclose(p);
  printf("netstat: lines=%d exit-status=%d\n", lines, st);
  return 0;
}
