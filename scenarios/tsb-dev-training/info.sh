#!/usr/bin/env bash

# Colors
end="\033[0m"
greenb="\033[1;32m"
lightblueb="\033[1;36m"

function print_info {
  echo -e "${greenb}${1}${end}"
}

print_info "the starting point for this scenario (tsb developer training) is a running management plane (t1) and two onboarded workload clusters (c1 and c2)"
