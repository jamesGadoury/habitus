# process.sh - aliases & functions for managing processes

psids() {
  if [ $# -eq 0 ]; then
    ps -eo pid,pgid,sid,comm
  else
    ps -eo pid,pgid,sid,comm | awk -v pat="$*" 'NR==1 || $0 ~ pat'
  fi
}
