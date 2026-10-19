# ❓ FAQ de aula — erros comuns e soluções

> ⬅️ [README principal](../README.md)

Antes de qualquer coisa, dois comandos resolvem ou explicam a maioria dos
problemas:

```bash
make status         # quem está no ar, quem é primário, quem é réplica?
make diagnostico    # relatório completo para mandar ao instrutor
```

E um terceiro, para ler o que o PostgreSQL de um nó está dizendo:

```bash
make logs n=replica1     # saia com Ctrl+C
```

---

## Subindo o ambiente

### `make verificar` diz que uma porta está ocupada

Outro programa da sua máquina está usando a porta. Abra o arquivo `.env`, na
raiz do repositório, e troque o número indicado na mensagem:

```bash
PORTA_PRIMARIO=5560        # era 5460
```

Rode `make verificar` de novo e depois `make subir`. As portas só importam
para conectar **de fora** (um DBeaver, por exemplo). A trilha inteira usa
`make psql`, que não depende delas.

### `docker: 'compose' is not a docker command`

Você tem o Compose antigo (v1), ou um Docker sem o Compose. No Linux:

```bash
sudo apt update && sudo apt install docker-compose-plugin   # ou docker-compose-v2, no Ubuntu
docker compose version
```

No Windows e no Mac, o Compose vem com o Docker Desktop: atualize o Docker
Desktop. Veja os guias: [Windows](./windows.md), [Mac](./mac.md),
[Linux](./linux.md).

### `permission denied while trying to connect to the Docker daemon`

O seu usuário não está no grupo `docker` (só acontece no Linux):

```bash
sudo usermod -aG docker $USER
```

Feche a sessão e entre de novo (ou reinicie) para valer. Detalhes no
[passo 2 do guia do Linux](./linux.md#passo-2--usar-o-docker-sem-sudo).

### `make: command not found`

O `make` é pré-requisito da trilha e não vem com o Docker. Veja a
[tabela de instalação](../README.md#-já-tenho-o-docker) ou o guia do seu
sistema: [Mac](./mac.md), [Linux](./linux.md). No Windows, você
provavelmente está no PowerShell: use o terminal do **Ubuntu** (veja
[Preparando o Windows](./windows.md)).

### Três nós aparecem como `esperando dados`. Deu errado?

Não. `replica1`, `replica2` e `restauracao` **nascem vazios de propósito**: o
container fica no ar, mas sem PostgreSQL, esperando você colocar dados na
pasta deles (etapas 3 a 5). É você quem os transforma em réplica ou em
servidor restaurado.

---

## Nós que não sobem

### `make reiniciar` diz que o container parou

O PostgreSQL não conseguiu ligar com o que está na pasta de dados. A mensagem
mostra as últimas linhas do log; as causas mais comuns:

| No log | Causa | Conserto |
|---|---|---|
| `syntax error in file ".../postgresql.auto.conf"` | erro de digitação numa linha que você acrescentou | veja abaixo |
| `could not locate required checkpoint record` / `invalid checkpoint record` | a cópia do backup ficou incompleta, ou faltou o `backup_label` | `make zerar n=<nó>` e copie o backup de novo |
| `recovery ended before configured recovery target was reached` | o WAL com o ponto de restauração não estava no arquivo | etapa 4, seção 4.6 (`pg_switch_wal`), depois `make zerar` e refaça a 4.7 |
| `requested timeline N is not a child of this server's history` | réplica apontando para um servidor de outra linha do tempo | `pg_rewind` (etapa 7) ou clonar de novo |

Para corrigir um arquivo de configuração de um nó que não sobe, use o
terminal com o nó desligado:

```bash
make bash-desligado n=restauracao
tail -10 $PGDATA/postgresql.auto.conf          # veja a linha errada
sed -i '/linha_errada/d' $PGDATA/postgresql.auto.conf
exit
make ligar n=restauracao
```

Na dúvida, para `replica1`, `replica2` e `restauracao`, recomeçar o nó é
mais rápido: `make zerar n=<nó>` e refaça a seção.

### `make bash-desligado` diz que o nó está LIGADO

Ele só funciona com o nó desligado (é para isso que ele existe). Rode
`make parar n=<nó>` antes.

### `make psql n=replica1` diz que o nó está esperando dados

Ainda não há PostgreSQL rodando nele. Você pulou a cópia dos dados (o
`pg_basebackup` da etapa 5 ou o `cp` do backup nas etapas 3 e 4), ou
copiou e não reiniciou o container (`make reiniciar n=<nó>`).

---

## Backup e PITR

### `pg_basebackup: error: directory "/var/lib/postgresql/data" exists but is not empty`

A pasta do nó já tem dados (de uma tentativa anterior). Esvazie e repita:

```bash
make zerar n=replica1
```

### `pg_restore: error: could not execute query: ERROR: relation "itens_pedidos" already exists`

A tabela já foi restaurada (talvez pela metade, numa tentativa anterior).
Apague-a e restaure de novo: `DROP TABLE itens_pedidos;` no psql do
`primario` e repita a seção 2.6.

### O `pg_stat_archiver` mostra `failed_count` maior que zero

O `archive_command` está falhando. Veja o motivo:

```bash
make logs n=primario     # procure por "archive command failed"
```

Quase sempre é a pasta `/backup/wal` que não existe (seção 4.2). Crie a pasta:
o PostgreSQL tenta de novo sozinho, e o `last_archived_time` volta a andar.

### Depois do failover (etapa 7), o `failed_count` não para de subir

No log aparece `archive command failed` para um segmento que **já está** em
`/backup/wal`. Um servidor tentou arquivar de novo um segmento arquivado
antes (é comum depois de split-brain e `pg_rewind`). Confira se o seu
`archive_command` tem o final `|| cmp -s %p /backup/wal/%f` (seção 4.2). Se
não tiver, acerte no primário atual; é `sighup`, não precisa reiniciar:

```sql
ALTER SYSTEM SET archive_command = 'test ! -f /backup/wal/%f && cp %p /backup/wal/%f || cmp -s %p /backup/wal/%f';
SELECT pg_reload_conf();
```

Se mesmo assim falhar, os dois arquivos têm o mesmo nome e conteúdos
**diferentes**: é um caso para o instrutor (`make diagnostico`).

### O `restauracao` subiu, mas com os preços errados (ou sem as vendas certas)

O alvo da recuperação não foi o que você queria. Confira no log onde ele
parou (`docker logs dbe_restauracao 2>&1 | grep "recovery stopping"`). Se a
linha não existe, ele reaplicou **todo** o WAL (o nome do ponto estava errado
ou faltou o `recovery.signal`). Recomece com `make zerar n=restauracao` e
refaça a seção 4.7.

---

## Replicação

### `no pg_hba.conf entry for replication connection from host ..., user "replicador"`

Falta a regra do `replicador` no `pg_hba.conf`, ou você esqueceu o
`SELECT pg_reload_conf();` depois de acrescentá-la (etapa 5, seção 5.1).

### `password authentication failed for user "replicador"`

O usuário foi criado com outra senha. A senha que os nós conhecem (no
`~/.pgpass` de cada um) é `replica123`. Acerte no `primario`:

```sql
ALTER ROLE replicador PASSWORD 'replica123';
```

### `replication slot "replica1" already exists`

Sobrou o slot de uma tentativa anterior. Apague-o no primário e repita:

```sql
SELECT pg_drop_replication_slot('replica1');
```

### A réplica está no ar, mas o `make status` mostra `LÊ DE = -`

Ela não está recebendo WAL. Leia o motivo:

```bash
make logs n=replica1
```

| No log | Conserto |
|---|---|
| `replication slot "X" does not exist` | crie o slot no primário atual: `SELECT pg_create_physical_replication_slot('X');` |
| `could not connect to the primary server` | o primário está desligado, ou o `primary_conninfo` aponta para o nó errado (etapa 7) |
| `requested WAL segment ... has already been removed` | a réplica ficou fora tempo demais sem slot: clone de novo (`make zerar` + `pg_basebackup`) |

### Quebrei as réplicas e quero recomeçar a etapa 6 ou 7

```bash
make gabarito-replicas
```

Ele apaga as duas réplicas, recria os slots e clona as duas de novo a partir
do `primario`. (Ele exige que o `primario` seja o primário. Se você parou no
meio da etapa 7, com a `replica1` como primário, termine o switchover ou
recomece tudo com `make limpar && make subir`.)

### O `INSERT` pendurou e não volta

Você está com a replicação síncrona ligada e nenhuma réplica síncrona no ar
(etapa 6, seção 6.3). Aperte `Ctrl+C` (a transação **fica gravada** no
primário). Depois, ligue as réplicas (`make ligar n=replica1`) ou desligue a
replicação síncrona, de **outra** janela do psql:

```sql
ALTER SYSTEM RESET synchronous_standby_names;
SELECT pg_reload_conf();
```

---

## Failover

### `pg_rewind: error: target server must be shut down cleanly`

Use `make parar n=<nó>` (desligamento limpo) antes do `make bash-desligado`.
O `pg_rewind` até sabe lidar com um servidor derrubado com `docker kill`
(ele faz a recuperação de queda antes), mas não com um servidor ligado.

### `pg_rewind: error: could not connect to server` ou `permission denied for function pg_ls_dir`

O nó de origem (`--source-server`) está desligado, ou faltaram os `GRANT`s da
seção 7.1. Os `GRANT`s são feitos no **primário atual**.

### O antigo primário voltou como primário (dois primários no `make status`)

É o split-brain da seção 7.5, e pode acontecer sem querer se você ligar o nó
antes do `pg_rewind`. Desligue-o **na hora** (`make parar n=primario`) e
siga a seção 7.6.

---

## Replicação lógica

### `logical decoding requires "wal_level" >= "logical"`

O `wal_level` não foi alterado, ou o `primario` não foi reiniciado depois do
`ALTER SYSTEM` (etapa 8, seção 8.1).

### `permission denied for table pessoas` (no log do `logico`)

Faltou o `GRANT SELECT ON ALL TABLES IN SCHEMA public TO replicador;` no
`primario` (seção 8.2). Depois do `GRANT`, a assinatura tenta de novo sozinha.

### A assinatura parou e os pedidos não chegam mais no `logico`

Algo travou a aplicação das mudanças. O motivo está no log:

```bash
docker logs dbe_logico 2>&1 | grep -E "ERROR|DETAIL" | tail -4
```

As duas causas da trilha são conflito de chave (seção 8.6) e coluna que não
existe no destino (seção 8.7).

---

## Particionamento

### `no partition of relation "pedidos_part" found for row`

Uma linha não coube em nenhuma partição e não existe partição `DEFAULT`. Crie
a `pedidos_default` (seção 9.4) e repita.

### `updated partition constraint for default partition "pedidos_default" would be violated by some row`

Você tentou criar a partição de um mês que já tem linhas na `DEFAULT`. É o
problema da seção 9.9 ("o que acontece daqui a quatro meses?"): as linhas
precisam sair da `DEFAULT` antes. Esse é um dos desafios do nível Pleno.

### A transação da seção 9.5 deu erro no meio

Como tudo está entre `BEGIN` e `COMMIT`, nada foi alterado. Rode
`ROLLBACK;` (se o psql ainda estiver dentro da transação), apague a tabela
nova (`DROP TABLE pedidos_part;`) e recomece da seção 9.4.

---

## Recomeçando

| Quero... | Comando |
|---|---|
| recomeçar um nó vazio (réplica ou restauração) | `make zerar n=<nó>` |
| ter as réplicas da etapa 5 prontas | `make gabarito-replicas` |
| recriar os containers sem perder dados | `make consertar` |
| recomeçar **tudo**, do zero | `make limpar && make subir` |

Não resolveu? Rode `make diagnostico`, copie a saída inteira e mande ao
instrutor.
