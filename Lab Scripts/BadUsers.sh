#!/bin/bash
p=0
inactivity_input=""
inactivity_days=""

function print_help {
  echo "Usage: $0 [-p] [-t <period>]"
  echo "  -p            Validate users with running processes (exclude them)"
  echo "  -t <period>   Specify inactivity threshold (e.g., 2d for days, 4m for months)"
}

# Parse options: -p and -t <period>
while [ $# -gt 0 ]; do
  case "$1" in
    "-p")
       p=1
       shift;;
    "-t")
       shift
       if [ -z "$1" ]; then
         echo "Error: -t requires a time period argument."
         exit 1
       fi
       inactivity_input=$1
       shift;;
    *)
       echo "Error: Unknown option: $1"
       print_help
       exit 1;;
  esac
done

# Convert the inactivity threshold to a number of days
if [ -n "$inactivity_input" ]; then
   unit="${inactivity_input: -1}"
   case "$unit" in
     d)
       inactivity_days=${inactivity_input%?}
       ;;
     m)
       num=${inactivity_input%?}
       inactivity_days=$(( num * 30 ))
       ;;
     *)
       inactivity_days=$inactivity_input
       ;;
   esac
fi

current_epoch=$(date +%s)

# Loop over each user from /etc/passwd
for user in $(cut -d: -f1 /etc/passwd); do
   home=$(grep "^$user:" /etc/passwd | cut -d: -f6)
   if [ -d "$home" ]; then
      num_files=$(find "$home" -type f -user "$user" 2>/dev/null | wc -l)
   else
      num_files=0
   fi

   if [ "$num_files" -eq 0 ]; then
      valid=1  # Assume this user is a candidate for being inactive
      if [ "$p" -eq 1 ]; then
         user_proc=$(pgrep -u "$user" | wc -l)
         if [ "$user_proc" -ne 0 ]; then
             valid=0
         fi
      fi

      if [ -n "$inactivity_days" ]; then
         # Obtain last login information using lastlog
         lastlog_line=$(lastlog -u "$user" | tail -n 1)
         if echo "$lastlog_line" | grep -q "Never logged in"; then
             last_login_epoch=0
         else
             last_login_str=$(lastlog -u "$user" | awk 'NR==2 {for(i=4;i<=NF;i++) printf $i " "; print ""}')
             last_login_epoch=$(date -d "$last_login_str" +%s 2>/dev/null)
             if [ -z "$last_login_epoch" ]; then
                last_login_epoch=0
             fi
         fi

         # Check if any file in the home directory was modified in the given period
         recent_mod=$(find "$home" -type f -user "$user" -mtime -"$inactivity_days" 2>/dev/null | wc -l)

         if [ "$last_login_epoch" -gt 0 ]; then
            diff_days=$(( (current_epoch - last_login_epoch) / 86400 ))
         else
            diff_days=$(( inactivity_days + 1 ))
         fi

         # User must meet both criteria of last login and file modification inactivity
         if [ "$diff_days" -lt "$inactivity_days" ] || [ "$recent_mod" -gt 0 ]; then
            valid=0
         fi
      fi

      if [ "$valid" -eq 1 ]; then
          echo "$user"
      fi
   fi
done
