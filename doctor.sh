#!/usr/bin/env bash
# Pendrive_X Doctor — Linux/macOS diagnostics
set -uo pipefail
RED='\033[1;91m'; GREEN='\033[1;92m'; YELLOW='\033[1;93m'; CYAN='\033[1;96m'; NC='\033[0m'
USB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -n "${1:-}" && -d "$1" ]] && USB_DIR="$(cd "$1" && pwd)"
echo -e "${CYAN}Pendrive_X Doctor — $USB_DIR${NC}"
echo "FS: $(df -T "$USB_DIR" 2>/dev/null | tail -1 || df -h "$USB_DIR" | tail -1)"
if command -v free &>/dev/null; then echo "RAM:"; free -h | head -2; fi
echo ""
if [[ -f "$USB_DIR/models/installed-models.txt" ]]; then echo "Installed models:"; cat "$USB_DIR/models/installed-models.txt"; else echo "No installed-models.txt"; fi
echo ""
echo "GGUF files:"; ls -lh "$USB_DIR/models"/*.gguf 2>/dev/null || echo " (none)"
echo ""
[[ -x "$USB_DIR/ollama/ollama" ]] && echo -e "${GREEN}Ollama: FOUND${NC}" || echo -e "${RED}Ollama: MISSING${NC}"
[[ -f "$USB_DIR/anythingllm/AnythingLLM.AppImage" ]] && echo -e "${GREEN}AppImage: FOUND${NC}" || echo "AppImage: missing (Linux)"
[[ -d "$USB_DIR/anythingllm_mac/AnythingLLM.app" ]] && echo -e "${GREEN}AnythingLLM.app: FOUND${NC}" || echo "AnythingLLM.app: missing (macOS)"
echo ""
if [[ -f "$USB_DIR/anythingllm_data/storage/.env" ]]; then echo ".env:"; cat "$USB_DIR/anythingllm_data/storage/.env"; else echo "No .env"; fi
echo ""
echo "Ports 11434-11445:"
for p in $(seq 11434 11445); do
  if command -v nc &>/dev/null; then nc -z 127.0.0.1 $p 2>/dev/null && echo " $p IN USE" || echo " $p free"
  else python3 -c "import socket; s=socket.socket(); exit(0 if s.connect_ex(('127.0.0.1',$p))==0 else 1)" 2>/dev/null && echo " $p IN USE" || echo " $p free"
  fi
done
echo ""
echo "Logs:"; ls -lh "$USB_DIR/installer_data/logs" 2>/dev/null || echo " no installer logs"; ls -lh "$USB_DIR/anythingllm_data/logs" 2>/dev/null || echo " no launcher logs"
echo ""
if command -v shellcheck &>/dev/null; then echo "shellcheck:"; shellcheck "$USB_DIR"/linux/*.sh "$USB_DIR/start-mac.command" 2>&1 | head -20; fi
