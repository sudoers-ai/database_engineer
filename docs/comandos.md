# ⌨️ Comandos

> ⬅️ [README principal](../README.md)

Todo `make` deste repositório é um atalho para um ou mais comandos `docker`.
Esta página mostra o que está por trás de cada um: serve para entender o que
o atalho faz e para investigar quando algo dá errado. Rode sempre na **pasta
raiz** do repositório.

> O `make` é pré-requisito da trilha. Se você ainda não tem, veja os
> [pré-requisitos](../README.md#-pré-requisitos). No Windows, tudo desta
> página é digitado no terminal do Ubuntu (WSL): veja
> [Preparando o Windows](./windows.md).

Nos comandos abaixo, `n=` escolhe o nó: `primario` (o padrão), `replica1`,
`replica2`, `restauracao` ou `logico`. O container de cada nó se chama
`dbe_<nó>`.

## Ambiente

| `make` | Comando equivalente |
|---|---|
| `make verificar` | `bash scripts/verificar.sh` |
| `make subir` | `docker compose up -d` e espera o `primario` e o `logico` |
| `make status` | `bash scripts/status.sh` (consulta cada nó com `pg_is_in_recovery()`, `pg_stat_wal_receiver`...) |
| `make derruba` | `docker compose down` |
| `make limpar` | `docker compose down -v` (o `-v` apaga os volumes: **todos os dados**) |
| `make logs n=replica1` | `docker compose logs -f --tail 50 replica1` |
| `make consertar` | `docker compose up -d --force-recreate` |
| `make diagnostico` | `bash scripts/diagnostico.sh` |

## Entrar nos nós

| `make` | Comando equivalente |
|---|---|
| `make psql n=replica1` | `docker exec -it dbe_replica1 psql -P pager=off -U sudoers -d liga_sudoers` (o `-P pager=off` evita que um resultado longo abra o paginador no meio de um bloco colado) |
| `make bash n=primario` | `docker exec -it -u postgres dbe_primario bash` |
| `make bash-desligado n=primario` | `docker compose run --rm --no-deps -e MODO_DESLIGADO=1 primario bash` |
| `make sql n=primario f=arquivo.sql` | `docker exec -i dbe_primario psql -v ON_ERROR_STOP=1 -U sudoers -d liga_sudoers -f /repo/arquivo.sql` |

> Dentro dos containers, a pasta do repositório aparece em `/repo` (somente
> leitura) e o storage de backup em `/backup` (compartilhado entre os nós).

O `make bash-desligado` merece uma explicação: alguns comandos (o
`pg_rewind`) só rodam com o PostgreSQL **parado**. Num container, parar o
PostgreSQL é parar o container. Então ele sobe um container **temporário**,
com o mesmo volume de dados e na mesma rede do nó, mas sem ligar o
PostgreSQL. Ao sair (`exit`), o container temporário some.

Dentro do `psql`:

| Comando | Faz |
|---|---|
| `\dt` | lista as tabelas |
| `\d tabela` | descreve uma tabela (colunas, chaves, triggers, partições) |
| `\d+ tabela` | idem, com mais detalhes (lista as partições) |
| `\x` | liga/desliga a exibição "em pé" (boa para linhas largas) |
| `\timing on` | mostra quanto tempo cada comando levou |
| `\watch 1` | repete a última consulta a cada segundo (pare com `Ctrl+C`) |
| `\gset` | guarda o resultado de uma consulta em variáveis do psql |
| `\q` | sai |

## Ligar, desligar e reiniciar nós

| `make` | Comando equivalente |
|---|---|
| `make reiniciar n=replica1` | `docker restart dbe_replica1` e espera aceitar conexões |
| `make parar n=replica1` | `docker stop dbe_replica1` (desligamento **limpo**) |
| `make ligar n=replica1` | `docker start dbe_replica1` e espera aceitar conexões |
| — | `docker kill dbe_primario` (desligamento **brusco**, como falta de energia) |
| `make zerar n=restauracao` | para o nó, apaga a pasta de dados dele e liga de novo (vazio, esperando dados) |

O `make zerar` só aceita `replica1`, `replica2` e `restauracao`. Para
recomeçar o `primario`, só recomeçando tudo: `make limpar && make subir`.

## Carga e conferência

| `make` | Comando equivalente |
|---|---|
| `make carga t=30` | `docker exec dbe_primario pgbench -n -U sudoers -d liga_sudoers -T 30 -c 4 -R 100 -f /repo/carga/vendas.sql` |
| `make carga t=10 r=0` | o mesmo, sem limite de vendas por segundo (mede o máximo) |
| `make carga n=replica1` | a carga num nó específico (depois de um failover, por exemplo) |
| `make conferir e=5` | `bash scripts/conferir.sh 5` |
| `make gabarito-replicas` | `bash scripts/gabarito_replicas.sh` (faz a etapa 5 sozinho) |

Parâmetros da carga: `t` = segundos, `r` = vendas por segundo (`0` = sem
limite), `c` = clientes simultâneos, `n` = nó.

## Comandos do PostgreSQL usados na trilha

| Ferramenta | Para que | Etapa |
|---|---|---|
| `pg_dump` | backup lógico de um banco | 2, 8, 9 |
| `pg_dumpall --globals-only` | backup dos usuários e senhas | 2 |
| `pg_restore` | restaura um dump custom ou diretório (inteiro ou em partes, com `-l`/`-L`) | 2 |
| `pg_basebackup` | backup físico; clona réplicas | 3, 4, 5 |
| `pg_verifybackup` | confere um backup físico contra o manifesto | 3 |
| `pg_waldump` | traduz o WAL para texto | 1 |
| `pg_rewind` | traz um antigo primário de volta como réplica | 7 |
| `pgbench` | gera carga (o `make carga`) | 1 a 9 |
