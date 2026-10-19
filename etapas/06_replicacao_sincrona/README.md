# 6️⃣ Replicação síncrona

> ⬅️ Anterior: [5. Replicação assíncrona](../05_replicacao_assincrona/README.md) · [README principal](../../README.md) · Etapa 6 de 10

> **A pergunta da diretoria:** "Podemos perder uma venda que o cliente viu
> confirmada?"

Com a replicação assíncrona, **sim**. Existe uma janela, normalmente de
milissegundos, entre o primário responder COMMIT e o WAL chegar à réplica. Se
o primário morrer exatamente nessa janela, o cliente viu "pedido confirmado"
e o pedido não existe em nenhum outro lugar.

A replicação **síncrona** fecha essa janela: o primário só responde COMMIT
depois que **uma réplica confirma** que recebeu o WAL. Nesta etapa você liga a
replicação síncrona, descobre o que acontece quando as réplicas caem e mede
quanto ela custa.

> **Pré-requisito:** as duas réplicas da etapa 5 no ar. Confira com
> `make status`. Se não as tiver, `make gabarito-replicas` cria as duas.

---

## 6.1 Ligando: `FIRST 1`

Quem decide quais réplicas são síncronas é o primário, pela configuração
`synchronous_standby_names`. Os nomes da lista são os `application_name` que
cada réplica usou ao se conectar (o `-d "application_name=..."` da etapa 5).

🐘 **No psql do `primario`** (`make psql n=primario`):

<!-- rodar: primario -->
```sql
ALTER SYSTEM SET synchronous_standby_names = 'FIRST 1 (replica1, replica2)';
SELECT pg_reload_conf();
SELECT pg_sleep(1);

SELECT application_name, sync_state, sync_priority
FROM pg_stat_replication ORDER BY 1;
```

```
 application_name | sync_state | sync_priority
------------------+------------+---------------
 replica1         | sync       |             1
 replica2         | potential  |             2
(2 rows)
```

`FIRST 1 (replica1, replica2)` quer dizer: "espere a confirmação de **1**
réplica, escolhendo **pela ordem** da lista". A `replica1` é a síncrona. A
`replica2` é a **potencial**: a reserva, que assume se a `replica1` sumir.

Uma escrita, agora, só recebe COMMIT depois de a `replica1` gravar o WAL no
disco dela:

<!-- rodar: primario -->
```sql
INSERT INTO teste_replicacao (modo) VALUES ('sincrono FIRST 1');
```

```
INSERT 0 1
```

Pareceu igual. A diferença está no que **não aconteceu**: não existe mais
nenhum instante em que esse pedido exista só no primário.

---

## 6.2 Uma réplica cai

🖥️ **No seu terminal:**

<!-- rodar: shell -->
```bash
make parar n=replica1
```

🐘 **No psql do `primario`:**

<!-- rodar: primario -->
```sql
SELECT application_name, sync_state FROM pg_stat_replication;

INSERT INTO teste_replicacao (modo) VALUES ('sincrono, so a replica2 no ar');
```

```
 application_name | sync_state
------------------+------------
 replica2         | sync
(1 row)

INSERT 0 1
```

A `replica2` foi promovida a síncrona na hora, e a loja nem percebeu. É por
isso que se usa **duas** réplicas com `FIRST 1`: uma pode cair.

---

## 6.3 As duas caem

🖥️ **No seu terminal:**

<!-- rodar: shell -->
```bash
make parar n=replica2
```

Agora, no 🐘 **psql do `primario`**, tente uma venda:

```sql
INSERT INTO teste_replicacao (modo) VALUES ('sincrono, nenhuma replica no ar');
```

<!-- teste: docker exec -d dbe_primario psql -U sudoers -d liga_sudoers -c "INSERT INTO teste_replicacao (modo) VALUES ('sincrono, nenhuma replica no ar')" && sleep 2 -->

O comando **não volta**. O psql fica parado, sem resposta. Não feche essa
janela.

Abra **outra janela** com o psql do `primario` (`make psql n=primario`) e
investigue:

<!-- rodar: primario -->
```sql
SELECT pid, wait_event_type, wait_event, state, left(query, 50) AS comando
FROM pg_stat_activity
WHERE wait_event = 'SyncRep';

SELECT id, modo FROM teste_replicacao WHERE modo LIKE '%nenhuma%';
```

```
 pid | wait_event_type | wait_event | state  |                      comando
-----+-----------------+------------+--------+----------------------------------------------------
 540 | IPC             | SyncRep    | active | INSERT INTO teste_replicacao (modo) VALUES ('sincr
(1 row)

 id | modo
----+------
(0 rows)
```

O `INSERT` está esperando (`wait_event = SyncRep`) por uma réplica que não
existe. E ninguém mais enxerga a linha: para o resto do mundo, essa transação
ainda não terminou.

**A loja parou de vender.** É a consequência direta da garantia que você
pediu: "nunca diga COMMIT sem uma réplica confirmar". Sem réplica, sem COMMIT.

Volte à primeira janela e aperte **`Ctrl+C`**:

<!-- teste: docker exec dbe_primario psql -U sudoers -d liga_sudoers -c "SELECT pg_cancel_backend(pid) FROM pg_stat_activity WHERE wait_event = 'SyncRep'" && sleep 1 -->

```
^CCancel request sent
WARNING:  canceling wait for synchronous replication due to user request
DETAIL:  The transaction has already committed locally, but might not have been replicated to the standby.
INSERT 0 1
```

Leia o `DETAIL` com atenção: "a transação **já foi gravada localmente**, mas
pode não ter sido replicada". Cancelar **não desfaz** o INSERT. Na segunda
janela:

<!-- rodar: primario -->
```sql
SELECT id, modo FROM teste_replicacao WHERE modo LIKE '%nenhuma%';
```

```
 id |              modo
----+---------------------------------
  5 | sincrono, nenhuma replica no ar
(1 row)
```

Duas lições que muita gente só aprende em produção:

1. **Replicação síncrona não é uma transação distribuída.** O primário grava
   primeiro e **depois espera**. Se a espera for interrompida, o dado fica no
   primário e em mais lugar nenhum.
2. **Nem o `statement_timeout` salva.** O tempo limite não vale para a
   espera síncrona: um aplicativo que confia nele fica pendurado para sempre.

Religue as réplicas.

🖥️ **No seu terminal:**

<!-- rodar: shell -->
```bash
make ligar n=replica1
make ligar n=replica2
sleep 2
make status
```

```
NÓ           SITUAÇÃO               PAPEL        TL  LSN          LÊ DE      RÉPLICAS PG
primario     no ar                  primário     1   0/15170D98   -          2        17
replica1     no ar                  réplica      1   0/15170D98   primario   0        17
replica2     no ar                  réplica      1   0/15170D98   primario   0        17
...
```

Elas voltam, pegam o WAL que os slots guardaram e recebem também a linha 5.

---

## 6.4 Quórum: `ANY 1`

Com `FIRST`, a ordem importa: a `replica1` é sempre a preferida. Com `ANY`, o
primário espera **qualquer** réplica da lista, a que responder primeiro:

🐘 **No psql do `primario`:**

<!-- rodar: primario -->
```sql
ALTER SYSTEM SET synchronous_standby_names = 'ANY 1 (replica1, replica2)';
SELECT pg_reload_conf();
SELECT pg_sleep(1);

SELECT application_name, sync_state FROM pg_stat_replication ORDER BY 1;

INSERT INTO teste_replicacao (modo) VALUES ('sincrono ANY 1');
```

```
 application_name | sync_state
------------------+------------
 replica1         | quorum
 replica2         | quorum
(2 rows)
...
INSERT 0 1
```

| Configuração | Espera por | Quando usar |
|---|---|---|
| `FIRST 1 (a, b)` | `a`; se `a` cair, `b` | uma réplica preferida (ex.: no mesmo data center) |
| `ANY 1 (a, b)` | a mais rápida das duas | réplicas equivalentes; a latência é a da mais rápida |
| `ANY 2 (a, b, c)` | duas quaisquer de três | dado que não pode se perder nem se **dois** servidores morrerem |
| `''` (vazio) | ninguém | assíncrono |

---

## 6.5 Quanto o COMMIT espera: `synchronous_commit`

A lista diz **quem** confirma. O `synchronous_commit` diz **o quê**. E ele
pode mudar **por transação**: cada sessão escolhe o nível que precisa.

| `synchronous_commit` | O COMMIT volta depois que... | Pode perder dado se... |
|---|---|---|
| `off` | ...o WAL está na **memória** do primário | o primário cair (até ~0,6 s de transações) |
| `local` | ...o WAL está no **disco** do primário | o disco do primário morrer |
| `remote_write` | ...a réplica **recebeu** o WAL (memória dela) | primário e réplica caírem juntos |
| `on` (padrão) | ...a réplica **gravou** o WAL no disco | primário e réplica perderem o disco |
| `remote_apply` | ...a réplica **reaplicou**: o dado já aparece numa consulta nela | idem ao `on` |

Sem réplica síncrona configurada, `remote_write`, `on` e `remote_apply` se
comportam como `local`.

A diferença entre `on` e `remote_apply` é a mesma entre `flush_lsn` e
`replay_lsn` da etapa 5. Veja na prática, congelando a reaplicação das duas
réplicas (elas continuam **recebendo e gravando** o WAL):

🐘 **No psql do `replica1`** (`make psql n=replica1`):

<!-- rodar: replica1 -->
```sql
SELECT pg_wal_replay_pause();
```

🐘 **No psql do `replica2`** (`make psql n=replica2`):

<!-- rodar: replica2 -->
```sql
SELECT pg_wal_replay_pause();
```

🐘 **No psql do `primario`:**

<!-- rodar: primario -->
```sql
SET synchronous_commit = on;
INSERT INTO teste_replicacao (modo) VALUES ('on, replay congelado');
```

```
SET
INSERT 0 1
```

Com `on`, voltou na hora: as réplicas **gravaram** o WAL, e isso basta. Agora
peça mais:

```sql
SET synchronous_commit = remote_apply;
INSERT INTO teste_replicacao (modo) VALUES ('remote_apply, replay congelado');
```

<!-- teste: docker exec -d dbe_primario psql -U sudoers -d liga_sudoers -c "SET synchronous_commit = remote_apply" -c "INSERT INTO teste_replicacao (modo) VALUES ('remote_apply, replay congelado')" && sleep 2 -->

Pendurou de novo: nenhuma réplica consegue **reaplicar**. Descongele só a
`replica1`:

🐘 **No psql do `replica1`:**

<!-- rodar: replica1 -->
```sql
SELECT pg_wal_replay_resume();
SELECT pg_sleep(1);
SELECT id, modo FROM teste_replicacao WHERE modo LIKE 'remote_apply%';
```

```
 id |              modo
----+--------------------------------
  8 | remote_apply, replay congelado
(1 row)
```

No mesmo instante o `INSERT` do primário voltou com `INSERT 0 1`: com `ANY 1`,
bastou **uma** réplica reaplicar. E a linha já está visível nela.

Descongele também a `replica2`.

🐘 **No psql do `replica2`:**

<!-- rodar: replica2 -->
```sql
SELECT pg_wal_replay_resume();
```

Para que serve o `remote_apply`? Para o caso em que o aplicativo **grava no
primário e logo em seguida lê da réplica** ("finalizei a compra; mostre meus
pedidos"). Com `on`, a réplica pode ainda não mostrar o pedido que acabou de
ser feito. Com `remote_apply`, mostra.

E o caminho inverso também vale: um sistema de logs, que pode perder um
segundo de dados, faz `SET synchronous_commit = local` (ou até `off`) e não
paga o custo da réplica.

---

## 6.6 O preço

Nada disso é de graça. Cada COMMIT síncrono espera uma ida e volta pela rede
**e** a gravação no disco da réplica. Meça, com o simulador sem limite de
velocidade (`r=0`):

🐘 **No psql do `primario`**, volte ao assíncrono por um instante:

<!-- rodar: primario -->
```sql
ALTER SYSTEM SET synchronous_standby_names = '';
SELECT pg_reload_conf();
```

🖥️ **No seu terminal:**

<!-- rodar: shell -->
```bash
make carga t=5 r=0
```

```
Simulando vendas em primario por 5s, sem limite de vendas/s...
...
latency average = 0.705 ms
tps = 5649.897277 (without initial connection time)
```

🐘 **No psql do `primario`**, de volta ao síncrono:

<!-- rodar: primario -->
```sql
ALTER SYSTEM SET synchronous_standby_names = 'ANY 1 (replica1, replica2)';
SELECT pg_reload_conf();
```

🖥️ **No seu terminal:**

<!-- rodar: shell -->
```bash
make carga t=5 r=0
```

```
Simulando vendas em primario por 5s, sem limite de vendas/s...
...
latency average = 1.092 ms
tps = 3656.339872 (without initial connection time)
```

Os seus números serão outros, mas a proporção costuma ser parecida: **um
terço a menos** de vendas por segundo, com os cinco servidores **na mesma
máquina**. Com réplicas em outro prédio ou em outra região da nuvem, a ida e
volta pela rede passa de 0,1 ms para 2 ms, 20 ms, 80 ms, e o custo explode.
É por isso que réplica síncrona costuma ficar **perto** do primário, e a
réplica distante (a de recuperação de desastre) fica assíncrona.

---

## 6.7 De volta ao assíncrono

Na próxima etapa você vai derrubar servidores de propósito, várias vezes. Com
a replicação síncrona ligada, cada queda pararia as vendas. Volte ao
assíncrono:

🐘 **No psql do `primario`:**

<!-- rodar: primario -->
```sql
ALTER SYSTEM RESET synchronous_standby_names;
SELECT pg_reload_conf();
SELECT pg_sleep(1);
SHOW synchronous_standby_names;
```

```
...
 synchronous_standby_names
---------------------------

(1 row)
```

O `ALTER SYSTEM RESET` apaga a linha do `postgresql.auto.conf` e volta ao
padrão. (O `pg_sleep(1)` existe porque o `pg_reload_conf()` só **pede** a
releitura da configuração: cada processo a relê logo em seguida, mas não no
mesmo instante. Sem a pausa, o `SHOW` ainda pode mostrar o valor antigo.)

> Em produção, a escolha é sua (e da diretoria): **síncrona** com pelo menos
> duas réplicas (`ANY 1` de 2) quando não se pode perder nenhuma transação
> confirmada; **assíncrona** quando milissegundos de perda são aceitáveis em
> troca de desempenho e disponibilidade.

---

## ✔️ Confira

🖥️ **No seu terminal:**

<!-- rodar: shell -->
```bash
make conferir e=6
```

```
Conferindo a etapa 6 - Replicação síncrona

  ✅ teste_replicacao tem as linhas de todos os testes (FIRST, ANY, nenhuma réplica, remote_apply)
  ✅ as linhas chegaram às duas réplicas, inclusive a gravada sem réplica no ar
  ✅ synchronous_standby_names vazio: o cluster voltou ao assíncrono
  ✅ replica1 e replica2 recebendo o WAL do primario

✅ Etapa 6 conferida.
```

---

# ➡️ Continue em [7. Failover e switchover](../07_failover/README.md)
