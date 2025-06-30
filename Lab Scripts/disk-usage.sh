#!/bin/bash

function print_help {
  echo "Usage: $0 [-g group] <space_limit>"
  echo "   -g group      Specify a group; only its users will be processed"
  echo "   <space_limit> Threshold for disk space usage (e.g., 600M, 500K)"
}

# Parse the optional -g option
group=""
if [ "$1" == "-g" ]; then
   if [ -z "$2" ]; then
      echo "Error: -g requires a group name."
      print_help
      exit 1
   fi
   group=$2
   shift 2
fi

if [ $# -ne 1 ]; then
  print_help
  exit 1
fi

space_limit_input=$1
unit="${space_limit_input: -1}"
value="${space_limit_input%?}"
case "$unit" in
  [Kk])
    space_limit=$(( value * 1024 ))
    ;;
  [Mm])
    space_limit=$(( value * 1024 * 1024 ))
    ;;
  [Gg])
    space_limit=$(( value * 1024 * 1024 * 1024 ))
    ;;
  *)
    space_limit=$space_limit_input
    ;;
esac

# Function to calculate disk usage (in bytes) for a user
function get_disk_usage {
  local user=$1
  usage=$(find / -xdev -user "$user" -printf "%s\n" 2>/dev/null | awk '{sum+=$1} END {print sum}')
  if [ -z "$usage" ]; then
    usage=0
  fi
  echo $usage
}

# Function to format the byte count into a human-readable form
function format_bytes {
  local bytes=$1
  if [ $bytes -ge $((1024 * 1024 * 1024)) ]; then
    printf "%.0f GB" $(echo "$bytes/1024/1024/1024" | bc -l)
  elif [ $bytes -ge $((1024 * 1024)) ]; then
    printf "%.0f MB" $(echo "$bytes/1024/1024" | bc -l)
  elif [ $bytes -ge 1024 ]; then
    printf "%.0f KB" $(echo "$bytes/1024" | bc -l)
  else
    printf "%d B" $bytes
  fi
}

# Build the list of users to process.
if [ -n "$group" ]; then
  # Get additional users from the group's member list (field 4 of /etc/group)
  users_list=$(grep "^$group:" /etc/group | cut -d: -f4 | tr ',' ' ')
  # Also include users with primary group equal to the group's GID.
  gid=$(grep "^$group:" /etc/group | cut -d: -f3)
  primary_users=$(awk -F: -v gid="$gid" '($4 == gid){print $1}' /etc/passwd)
  users_list="$users_list $primary_users"
else
  users_list=$(cut -d: -f1 /etc/passwd)
fi

# Remove any duplicate usernames
users_list=$(echo $users_list | tr ' ' '\n' | sort | uniq)
total_group_usage=0

echo "Disk usage per user:"
for user in $users_list; do
  usage=$(get_disk_usage "$user")
  total_group_usage=$(( total_group_usage + usage ))
  formatted_usage=$(format_bytes $usage)
  echo "$user $formatted_usage"
  # If disk usage exceeds the threshold, place a warning message in the user's .bash_profile
  if [ $usage -gt $space_limit ]; then
    profile=$(eval echo "~$user/.bash_profile")
    warning="# WARNING: Your disk usage ($(format_bytes $usage)) exceeds the limit ($(format_bytes $space_limit)). Please delete or compress files to free up space. Remove this message once resolved."
    if [ -f "$profile" ]; then
      if ! grep -q "WARNING: Your disk usage" "$profile"; then
         echo "$warning" >> "$profile"
      fi
    else
      echo "$warning" > "$profile"
    fi
  fi
done

# If a group is specified, print the total group disk usage as well
if [ -n "$group" ]; then
  formatted_total=$(format_bytes $total_group_usage)
  echo "Total disk usage for group $group: $formatted_total"
fi

