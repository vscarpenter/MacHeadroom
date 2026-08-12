// PortTableABI.h — xnu pcblist_n record layouts (not in the public SDK).
// Copied for sysctl net.inet.{tcp,udp}.pcblist_n parsing; see
// Evidence/ports-spike/ and SANDBOX_NOTES.md "Port enumeration spike".
// The PortsSamplerLiveTests netstat cross-check is the oracle for these
// copies: if it fails, re-derive from xnu source before changing anything.
#ifndef PORT_TABLE_ABI_H
#define PORT_TABLE_ABI_H

#include <netinet/in.h>
#include <sys/types.h>

#define MH_XSO_SOCKET 0x001
#define MH_XSO_RCVBUF 0x002
#define MH_XSO_SNDBUF 0x004
#define MH_XSO_STATS  0x008
#define MH_XSO_INPCB  0x010
#define MH_XSO_TCPCB  0x020

#define MH_TCPS_LISTEN 1

// xnu declares every one of these structures inside #pragma pack(4)
// regions (bsd/netinet/in_pcb.h line ~554, bsd/sys/socketvar.h,
// bsd/netinet/tcp_var.h). Without it, natural alignment pads so_pcb to
// an 8-byte boundary and every later field — including so_last_pid —
// shifts by 4, silently reading zeros. Found live by the netstat
// cross-check test.
#pragma pack(4)

struct mh_xinpgen {
  u_int32_t xig_len;
  u_int32_t xig_count;
  u_int64_t xig_gen;
  u_int64_t xig_sogen;
};

struct mh_xgen_n {
  u_int32_t xgn_len;
  u_int32_t xgn_kind;
};

// Complete copy of xnu's struct xsocket_n: so_last_pid / so_e_pid are
// the last fields, so no prefix trick is possible here.
struct mh_xsocket_n {
  u_int32_t xso_len;
  u_int32_t xso_kind;
  u_int64_t xso_so;
  short so_type;
  u_int32_t so_options;
  short so_linger;
  short so_state;
  u_int64_t so_pcb;
  int xso_protocol;
  int xso_family;
  short so_qlen;
  short so_incqlen;
  short so_qlimit;
  short so_timeo;
  u_short so_error;
  pid_t so_pgid;
  u_int32_t so_oobmark;
  uid_t so_uid;
  pid_t so_last_pid;
  pid_t so_e_pid;
};

// Prefix of xnu's struct xinpcb_n through the ports; records are longer
// (xgn_len governs advancement), we only read these fields.
struct mh_xinpcb_n_prefix {
  u_int32_t xi_len;
  u_int32_t xi_kind;
  u_int64_t xi_inpp;
  u_short inp_fport;
  u_short inp_lport;
};

// Prefix of xnu's struct xtcpcb_n through t_state (t_timer is
// TCPT_NTIMERS_EXT == 4 ints).
struct mh_xtcpcb_n_prefix {
  u_int32_t xt_len;
  u_int32_t xt_kind;
  u_int64_t t_segq;
  int t_dupacks;
  int t_timer[4];
  int t_state;
};

#pragma pack()

#endif
