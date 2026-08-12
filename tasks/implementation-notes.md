# Ports view — implementation ledger

Tactical deviations and discoveries during plan execution
(docs/superpowers/plans/2026-08-01-ports-view.md). Distill into
lessons/CLAUDE.md and delete before ending.

## Deviations from the plan as written

1. **`#pragma pack(4)` was missing from the plan's ABI header.** xnu
   wraps every pcblist struct in pack(4) (in_pcb.h ~line 554,
   socketvar.h, tcp_var.h). Without it, natural alignment pads
   `so_pcb` to an 8-byte boundary and everything downstream shifts +4:
   `so_last_pid` read as `so_e_pid` (usually 0). Symptom: ports parsed
   perfectly, every pid was 0. Packed sizes: xsocket_n 76 (not 80),
   xinpcb_n prefix 20 (not 24). The netstat cross-check caught it on
   first run — exactly what the test exists for.

2. **Record emission order is INPCB → SOCKET → bufs → stats → TCPCB**
   (xnu `get_pcblist_n`, bsd/netinet/in_pcblist.c), not SOCKET-first as
   the plan's parser assumed. Symptom: pid lagged one entry behind its
   port (ours "80:913" vs netstat "58906:913"). Parser restructured:
   XSO_INPCB starts an entry, XSO_SOCKET/XSO_TCPCB attach to it, entry
   emits on the next INPCB or end-of-walk. Entries without a SOCKET
   record are skipped (never fabricate a pid). Added the two-entry
   anti-shift regression test.

3. **Synthetic fixture records must be longer than 24 bytes.** The
   trailing-xinpgen terminator check (netstat's own heuristic:
   `xgn_len <= sizeof(xinpgen)` = end) means a prefix-sized 24-byte
   fixture record false-terminates the walk. Fixtures now carry
   realistic lengths (inpcb 128, tcpcb 224) with padding.

4. **netstat -anv's state field is 5 hex digits, not octal.** The
   test's pid-extraction regex `[0-7]{5}` silently dropped every line
   whose state contained 8 (launchd's 00180, bdagentd's 00080), which
   looked like our parser over-reporting. `[0-9a-f]{5}` fixed it; the
   disputed sockets were real and netstat agreed all along.

## Environment quirks

- zsh here chokes on bare `===` in compound commands (`== not found`)
  — avoid decorative separators in Bash calls.
- `head` in PATH is Homebrew gnubin; sandboxed children can't exec it.
  Absolute /usr/bin paths or no pipelines inside sandboxed popen.
