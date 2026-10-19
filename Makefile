# ==========================================================================
# Liga Sudoers - Database Engineering - atalhos
#
#   make ajuda      lista tudo
#
# Nada aqui e obrigatorio: todo `make` corresponde a um comando `docker`
# que esta escrito em docs/comandos.md. O Makefile so poupa digitacao.
#
# Os nos do cluster:  primario  replica1  replica2  restauracao  logico
# ==========================================================================
.DEFAULT_GOAL := ajuda
SHELL := /bin/bash
DC    := docker compose
n     ?= primario
t     ?= 30
c     ?= 4
r     ?= 100

# Cria o .env na primeira vez (so para voce poder trocar uma porta ocupada).
$(shell [ -f .env ] || cp .env.example .env 2>/dev/null)

.PHONY: ajuda verificar subir status derruba limpar logs consertar diagnostico \
        psql bash bash-desligado sql reiniciar parar ligar zerar carga \
        conferir gabarito-replicas

ajuda:  ## mostra esta ajuda
	@echo ""
	@echo "  Liga Sudoers - Database Engineering"
	@echo "  ---------------------------------------------------------------"
	@grep -E '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
	  | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[1m%-20s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "  n=<no> escolhe o no: primario (padrao), replica1, replica2, restauracao, logico"
	@echo ""

# ---------------------------------------------------------------- ambiente
verificar:   ## confere Docker, portas e memoria ANTES de subir
	@bash scripts/verificar.sh

subir:       ## sobe o cluster e espera o primario ficar pronto
	$(DC) up -d
	@bash scripts/esperar.sh primario logico
	@echo ""
	@echo "  Tudo no ar. Continue em etapas/01_primario/README.md"
	@echo ""

status:      ## mostra cada no: no ar? primario ou replica? timeline? LSN?
	@bash scripts/status.sh

derruba:     ## para os containers (MANTEM os dados)
	$(DC) down

limpar:      ## para tudo e APAGA os dados de todos os nos (recomeca do zero)
	$(DC) down -v

logs:        ## segue o log de um no (make logs n=replica1)
	$(DC) logs -f --tail 50 $(n)

consertar:   ## recria os containers (NAO apaga os dados)
	$(DC) up -d --force-recreate
	@bash scripts/esperar.sh primario logico

diagnostico: ## junta tudo que o instrutor precisa para te ajudar
	@bash scripts/diagnostico.sh

# ------------------------------------------------------------------- nos
psql:        ## abre o psql em um no (make psql n=replica1) - saia com \q
	@bash scripts/psql.sh $(n)

bash:        ## abre um terminal DENTRO do no, como usuario postgres (saia com exit)
	@docker exec -it -u postgres dbe_$(n) bash

bash-desligado: ## terminal com a pasta de dados de um no DESLIGADO (para pg_rewind)
	@bash scripts/desligado.sh $(n)

sql:         ## roda um arquivo .sql em um no (make sql n=primario f=entregas/x.sql)
	@test -n "$(f)" || (echo "uso: make sql n=primario f=caminho/do/arquivo.sql" && exit 1)
	@docker exec -i dbe_$(n) psql -v ON_ERROR_STOP=1 -U sudoers -d liga_sudoers -f /repo/$(f)

reiniciar:   ## reinicia um no e espera ele aceitar conexoes (make reiniciar n=replica1)
	docker restart dbe_$(n)
	@bash scripts/esperar.sh $(n)

parar:       ## desliga um no de forma limpa (make parar n=replica1)
	docker stop dbe_$(n)

ligar:       ## liga um no que foi desligado (make ligar n=replica1)
	docker start dbe_$(n)
	@bash scripts/esperar.sh $(n)

zerar:       ## APAGA a pasta de dados de um no vazio (replica1, replica2, restauracao)
	@bash scripts/zerar.sh $(n)

carga:       ## simula vendas (make carga t=30 r=100 n=primario; r=0 = sem limite)
	@echo "Simulando vendas em $(n) por $(t)s, $(if $(filter-out 0,$(r)),$(r) vendas/s,sem limite de vendas/s)..."
	@set -o pipefail; docker exec dbe_$(n) pgbench -n -U sudoers -d liga_sudoers -T $(t) -c $(c) -P 5 $(if $(filter-out 0,$(r)),-R $(r)) \
	  -f /repo/carga/vendas.sql 2>&1 | grep -E "^progress|^number of transactions actually|^tps|^latency average|^pgbench: error|ERROR"

# ------------------------------------------------------------- conferencia
conferir:    ## confere se a etapa foi feita (make conferir e=5)
	@test -n "$(e)" || (echo "uso: make conferir e=5   (o numero da etapa)" && exit 1)
	@bash scripts/conferir.sh $(e)

gabarito-replicas: ## ATALHO: cria replica1 e replica2 (a etapa 5 pronta)
	@bash scripts/gabarito_replicas.sh
