#!/usr/bin/env bash
# ==========================================================================
# Confere o terreno ANTES de subir o cluster: Docker, Compose v2, portas e
# memoria. A maior parte dos problemas de aula e porta ocupada - e e bem
# mais facil corrigir antes do que depois.
# ==========================================================================
set -uo pipefail
cd "$(dirname "$0")/.." && . scripts/comum.sh
[ -f .env ] && set -a && . ./.env && set +a
erros=0
erro_() { erro "$@"; erros=$((erros + 1)); }

echo
echo -e "${N}Conferindo o ambiente${F}"
echo

if ! command -v docker >/dev/null 2>&1; then
  erro_ "Docker não encontrado. Instale: https://docs.docker.com/get-docker/"
  echo; exit 1
fi
if ! docker info >/dev/null 2>&1; then
  erro_ "O Docker está instalado, mas não responde. Ele está aberto? (no Linux: sudo systemctl start docker)"
  echo "       Se a mensagem for 'permission denied', veja docs/faq.md"
  echo; exit 1
fi
ok "Docker respondendo ($(docker --version | awk '{print $3}' | tr -d ','))"

if docker compose version >/dev/null 2>&1; then
  ok "Docker Compose v2 ($(docker compose version --short 2>/dev/null))"
else
  erro_ "Falta o Docker Compose v2. O comando é 'docker compose' (com espaço), não 'docker-compose'."
  echo "       Linux: sudo apt install docker-compose-plugin"
fi

porta_ocupada() {
  local p="$1"
  if command -v ss >/dev/null 2>&1; then
    ss -ltn 2>/dev/null | awk '{print $4}' | grep -qE "[:.]${p}\$"
  elif command -v lsof >/dev/null 2>&1; then
    lsof -iTCP:"$p" -sTCP:LISTEN >/dev/null 2>&1
  else
    (exec 3<>"/dev/tcp/127.0.0.1/$p") >/dev/null 2>&1
  fi
}

conferir_porta() {
  local no="$1" porta="$2" variavel="$3"
  if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "dbe_$no"; then
    ok "porta $porta ($no) em uso pelo próprio dbe_$no — já está no ar"
  elif porta_ocupada "$porta"; then
    erro_ "porta $porta ($no) está ocupada por outro programa."
    echo "       Abra o arquivo .env e troque $variavel=$porta por outra, ex.: $variavel=$((porta + 100))"
  else
    ok "porta $porta livre ($no)"
  fi
}
conferir_porta primario    "${PORTA_PRIMARIO:-5460}"    PORTA_PRIMARIO
conferir_porta replica1    "${PORTA_REPLICA1:-5461}"    PORTA_REPLICA1
conferir_porta replica2    "${PORTA_REPLICA2:-5462}"    PORTA_REPLICA2
conferir_porta restauracao "${PORTA_RESTAURACAO:-5463}" PORTA_RESTAURACAO
conferir_porta logico      "${PORTA_LOGICO:-5464}"      PORTA_LOGICO

mem_kb=$(docker info --format '{{.MemTotal}}' 2>/dev/null || echo 0)
mem_gb=$(( mem_kb / 1024 / 1024 / 1024 ))
if [ "$mem_gb" -ge 2 ]; then
  ok "memória disponível para o Docker: ${mem_gb} GB"
else
  aviso "memória para o Docker abaixo de 2 GB. Aumente em Docker Desktop > Settings > Resources."
fi

echo
if [ "$erros" -gt 0 ]; then
  echo -e "${R}${erros} problema(s) acima.${F} Corrija e rode ${N}make verificar${F} de novo."
  echo "Dúvidas: docs/faq.md"
  echo; exit 1
fi
echo -e "${V}Tudo certo.${F} Próximo passo: ${N}make subir${F}"
echo
