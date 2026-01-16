#!/usr/bin/env bash
set -euo pipefail

# System Health Check Script
# Provides quick overview of container status, disk space, memory, and swap usage

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

print_header() {
  echo ""
  echo -e "${BOLD}═════════════════════════════════════════════════${NC}"
  echo -e "${BOLD}  🏠 Home Server Health Check${NC}"
  echo -e "${BOLD}  $(date '+%Y-%m-%d %H:%M:%S')${NC}"
  echo -e "${BOLD}═════════════════════════════════════════════════${NC}"
  echo ""
}

check_disk_space() {
  echo -e "${CYAN}━━━ 💾 Disk Space ━━━${NC}"
  
  # Check root filesystem
  local root_used
  root_used=$(df -h / | awk 'NR==2 {print $5}' | tr -d '%')
  local root_avail
  root_avail=$(df -h / | awk 'NR==2 {print $4}')
  
  if (( root_used >= 90 )); then
    echo -e "  ${RED}✗${NC} Root: ${root_used}% used (${root_avail} free) ${RED}CRITICAL${NC}"
  elif (( root_used >= 80 )); then
    echo -e "  ${YELLOW}⚠${NC} Root: ${root_used}% used (${root_avail} free) ${YELLOW}WARNING${NC}"
  else
    echo -e "  ${GREEN}✓${NC} Root: ${root_used}% used (${root_avail} free)"
  fi
  
  # Check data drive if it exists
  if df -h /media/data >/dev/null 2>&1; then
    local data_used
    data_used=$(df -h /media/data | awk 'NR==2 {print $5}' | tr -d '%')
    local data_avail
    data_avail=$(df -h /media/data | awk 'NR==2 {print $4}')
    
    if (( data_used >= 90 )); then
      echo -e "  ${RED}✗${NC} Data: ${data_used}% used (${data_avail} free) ${RED}CRITICAL${NC}"
    elif (( data_used >= 85 )); then
      echo -e "  ${YELLOW}⚠${NC} Data: ${data_used}% used (${data_avail} free) ${YELLOW}WARNING${NC}"
    else
      echo -e "  ${GREEN}✓${NC} Data: ${data_used}% used (${data_avail} free)"
    fi
  fi
  echo ""
}

check_memory() {
  echo -e "${CYAN}━━━ 🧠 Memory & Swap ━━━${NC}"
  
  # Parse free output
  local mem_total mem_used mem_free mem_avail
  read -r mem_total mem_used mem_free mem_avail <<< "$(free -h | awk 'NR==2 {print $2, $3, $4, $7}')"
  
  local mem_used_pct
  mem_used_pct=$(free | awk 'NR==2 {printf "%.0f", ($3/$2)*100}')
  
  if (( mem_used_pct >= 90 )); then
    echo -e "  ${RED}✗${NC} RAM: ${mem_used}/${mem_total} (${mem_used_pct}%) ${RED}CRITICAL${NC}"
  elif (( mem_used_pct >= 75 )); then
    echo -e "  ${YELLOW}⚠${NC} RAM: ${mem_used}/${mem_total} (${mem_used_pct}%) ${YELLOW}HIGH${NC}"
  else
    echo -e "  ${GREEN}✓${NC} RAM: ${mem_used}/${mem_total} (${mem_used_pct}%)"
  fi
  echo -e "  ${BLUE}ℹ${NC} Available: ${mem_avail}"
  
  # Check swap
  local swap_total swap_used
  read -r swap_total swap_used <<< "$(free -h | awk 'NR==3 {print $2, $3}')"
  
  if [[ "${swap_total}" != "0B" ]]; then
    local swap_used_pct
    swap_used_pct=$(free | awk 'NR==3 {if($2>0) printf "%.0f", ($3/$2)*100; else print "0"}')
    
    if (( swap_used_pct >= 50 )); then
      echo -e "  ${RED}✗${NC} Swap: ${swap_used}/${swap_total} (${swap_used_pct}%) ${RED}HIGH - Check swappiness!${NC}"
    elif (( swap_used_pct >= 25 )); then
      echo -e "  ${YELLOW}⚠${NC} Swap: ${swap_used}/${swap_total} (${swap_used_pct}%)"
    else
      echo -e "  ${GREEN}✓${NC} Swap: ${swap_used}/${swap_total} (${swap_used_pct}%)"
    fi
  fi
  echo ""
}

check_containers() {
  echo -e "${CYAN}━━━ 🐳 Docker Containers ━━━${NC}"
  
  if ! docker info >/dev/null 2>&1; then
    echo -e "  ${RED}✗ Docker is not running${NC}"
    return
  fi
  
  local total running stopped
  total=$(docker ps -a --format '{{.Names}}' | wc -l)
  running=$(docker ps --format '{{.Names}}' | wc -l)
  stopped=$((total - running))
  
  if (( stopped > 0 )); then
    echo -e "  ${YELLOW}⚠${NC} Containers: ${running}/${total} running (${stopped} stopped)"
  else
    echo -e "  ${GREEN}✓${NC} Containers: ${running}/${total} running"
  fi
  
  # Show stopped containers if any
  if (( stopped > 0 )); then
    echo -e "\n  ${YELLOW}Stopped containers:${NC}"
    docker ps -a --filter "status=exited" --format "    • {{.Names}} (exited {{.Status}})"
  fi
  
  # Check for recently restarted containers
  local recent_restarts
  recent_restarts=$(docker ps --format '{{.Names}}\t{{.Status}}' | grep -c 'seconds ago\|minute ago' || true)
  
  if (( recent_restarts > 0 )); then
    echo -e "\n  ${YELLOW}⚠ Recently restarted:${NC}"
    docker ps --format '{{.Names}}\t{{.Status}}' | grep 'seconds ago\|minute ago' | awk '{printf "    • %s (%s)\n", $1, $2, $3, $4}'
  fi
  echo ""
}

check_system_load() {
  echo -e "${CYAN}━━━ ⚡ System Load ━━━${NC}"
  
  local load1 load5 load15
  read -r load1 load5 load15 <<< "$(uptime | awk -F'load average:' '{print $2}' | tr -d ' ')"
  
  local cpu_count
  cpu_count=$(nproc)
  
  # Calculate load percentage (load1 / cpu_count * 100)
  local load_pct
  load_pct=$(awk "BEGIN {printf \"%.0f\", (${load1}/${cpu_count})*100}")
  
  if (( load_pct >= 100 )); then
    echo -e "  ${RED}✗${NC} Load: ${load1}, ${load5}, ${load15} (1, 5, 15 min) ${RED}OVERLOADED${NC}"
  elif (( load_pct >= 80 )); then
    echo -e "  ${YELLOW}⚠${NC} Load: ${load1}, ${load5}, ${load15} (1, 5, 15 min) ${YELLOW}HIGH${NC}"
  else
    echo -e "  ${GREEN}✓${NC} Load: ${load1}, ${load5}, ${load15} (1, 5, 15 min)"
  fi
  echo -e "  ${BLUE}ℹ${NC} CPU cores: ${cpu_count}"
  echo ""
}

check_services() {
  echo -e "${CYAN}━━━ 🌐 Critical Services ━━━${NC}"
  
  local services=("traefik" "prometheus" "grafana" "authentik-server" "postgres")
  
  for service in "${services[@]}"; do
    if docker ps --format '{{.Names}}' | grep -q "^${service}$"; then
      local status
      status=$(docker ps --format '{{.Names}}\t{{.Status}}' | grep "^${service}" | awk '{print $2, $3}')
      echo -e "  ${GREEN}✓${NC} ${service}: ${status}"
    else
      echo -e "  ${RED}✗${NC} ${service}: NOT RUNNING"
    fi
  done
  echo ""
}

print_summary() {
  echo -e "${CYAN}━━━ 📊 Quick Stats ━━━${NC}"
  
  # Uptime
  local uptime_str
  uptime_str=$(uptime -p | sed 's/up //')
  echo -e "  ${BLUE}ℹ${NC} Uptime: ${uptime_str}"
  
  # Docker stats for top consumers
  echo -e "  ${BLUE}ℹ${NC} Top 5 memory consumers:"
  docker stats --no-stream --format "table {{.Name}}\t{{.MemUsage}}" | tail -n +2 | sort -k2 -h -r | head -5 | awk '{printf "      %s: %s\n", $1, $2}'
  
  echo ""
}

print_footer() {
  echo -e "${BOLD}═════════════════════════════════════════════════${NC}"
  echo -e "${GREEN}✓ Health check complete${NC}"
  echo ""
  echo "For detailed metrics, visit: http://localhost:3000 (Grafana)"
  echo "For container logs: docker compose logs <service-name> --tail=50"
  echo "For resource limits: docker stats"
  echo ""
}

# Main execution
main() {
  print_header
  check_disk_space
  check_memory
  check_system_load
  check_containers
  check_services
  print_summary
  print_footer
}

main
