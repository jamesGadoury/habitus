# process.sh - aliases & functions for managing processes

psids() {
  if [ $# -eq 0 ]; then
    ps -eo pid,pgid,sid,comm
  else
    ps -eo pid,pgid,sid,comm | awk -v pat="$*" '
      NR == 1 { print; next }
      {
        lines[NR] = $0
        pgid_of[NR] = $2
        sid_of[NR] = $3
        if ($0 ~ pat) { keep_pgid[$2] = 1; keep_sid[$3] = 1 }
      }
      END {
        for (i = 2; i <= NR; i++)
          if (keep_pgid[pgid_of[i]] || keep_sid[sid_of[i]]) print lines[i]
      }
    '
  fi
}
