# 5️⃣ Replicação física assíncrona

> ⬅️ Anterior: [4. PITR](../04_pitr/README.md) · [README principal](../../README.md) · Etapa 5 de 10

> **A pergunta da diretoria:** "O servidor caiu. Quanto tempo ficamos fora?"

Com o PITR, voltar de um desastre leva minutos ou horas: copiar o backup,
reaplicar o WAL, apontar a aplicação. Para cair e voltar em **segundos**, é
preciso ter outro servidor **já ligado**, com os dados **já em dia**.

Isso é uma **réplica**: um servidor que recebe o WAL do primário **ao vivo**,
pela rede, e reaplica sem parar. Pense nela como um PITR que nunca termina.
Nesta etapa você transforma `replica1` e `replica2` em réplicas do `primario`.

---

## 5.1 O primário precisa autorizar

Uma réplica conversa com o primário pelo **protocolo de replicação**, o mesmo
que o `pg_basebackup` usou nas etapas 3 e 4. Dentro do próprio servidor isso
era permitido. Vindo de **outra máquina**, não é, e por bons motivos: quem
recebe o WAL recebe **todos os dados** do servidor.

São dois passos: um **usuário** com permissão de replicação e uma **regra de
acesso** que o deixe entrar.

🐘 **No psql do `primario`** (`make psql n=primario`):

<!-- rodar: primario -->
```sql
CREATE ROLE replicador WITH LOGIN REPLICATION PASSWORD 'replica123';
```

```
CREATE ROLE
```

O `replicador` **não é superusuário**: ele só pode replicar. É o princípio do
menor privilégio. Se a senha dele vazar, o estrago é menor do que se fosse a
do `sudoers`.

Agora a "portaria" do PostgreSQL, o `pg_hba.conf`:

<!-- rodar: primario -->
```sql
SELECT line_number, type, database, user_name, address, auth_method
FROM pg_hba_file_rules;
```

```
 line_number | type  |   database    | user_name |  address  |  auth_method
-------------+-------+---------------+-----------+-----------+---------------
         117 | local | {all}         | {all}     |           | trust
         119 | host  | {all}         | {all}     | 127.0.0.1 | trust
         121 | host  | {all}         | {all}     | ::1       | trust
         124 | local | {replication} | {all}     |           | trust
         125 | host  | {replication} | {all}     | 127.0.0.1 | trust
         126 | host  | {replication} | {all}     | ::1       | trust
         128 | host  | {all}         | {all}     | all       | scram-sha-256
(7 rows)
```

Cada linha é uma regra: **tipo de conexão**, **banco**, **usuário**, **de
onde** e **como se autentica**. O PostgreSQL lê de cima para baixo e usa a
primeira que combina. Repare: `database = all` **não inclui** conexões de
replicação. Replicação só vindo da própria máquina (`127.0.0.1`). Falta uma
regra para as réplicas.

📦 **No terminal do `primario`** (`make bash n=primario`):

<!-- rodar: bash-primario -->
```bash
echo "host replication replicador samenet scram-sha-256" >> $PGDATA/pg_hba.conf
tail -2 $PGDATA/pg_hba.conf
```

```
host all all all scram-sha-256
host replication replicador samenet scram-sha-256
```

A regra diz: conexões de **replicação**, do usuário **replicador**, vindas da
**mesma rede** do servidor (`samenet`), com senha (`scram-sha-256`). Em
produção, no lugar de `samenet` vai o IP exato de cada réplica.

O `pg_hba.conf` é `sighup`: basta recarregar.

🐘 **No psql do `primario`:**

<!-- rodar: primario -->
```sql
SELECT pg_reload_conf();

SELECT line_number, type, database, user_name, address, auth_method
FROM pg_hba_file_rules WHERE user_name = '{replicador}';
```

```
 pg_reload_conf
----------------
 t
(1 row)

 line_number | type |   database    |  user_name   | address | auth_method
-------------+------+---------------+--------------+---------+---------------
         129 | host | {replication} | {replicador} | samenet | scram-sha-256
(1 row)
```

---

## 5.2 Clonando o primário

Uma réplica começa como uma **cópia física** do primário, exatamente como o
backup da etapa 3. A diferença é que, em vez de ligar e promover, ela liga e
**continua pedindo WAL**.

Entre no `replica1`. Ele está esperando dados desde que o cluster subiu.

🖥️ **No seu terminal:**

```bash
make bash n=replica1
```

📦 **No terminal do `replica1`:**

<!-- rodar: bash-replica1 -->
```bash
pg_basebackup -h primario -U replicador -D $PGDATA \
  -d "application_name=replica1" -R -Xs -C -S replica1 -P
```

```
75321/75321 kB (100%), 1/1 tablespace
```

O mesmo `pg_basebackup` da etapa 3, com quatro novidades:

| Opção | Significa |
|---|---|
| `-h primario -U replicador` | copia **pela rede**, do `primario`, com o usuário de replicação |
| `-d "application_name=replica1"` | o **nome** com que esta réplica vai se apresentar ao primário (vai importar na etapa 6) |
| `-R` | já deixa a cópia configurada como réplica (veja abaixo) |
| `-C -S replica1` | cria no primário um ***replication slot*** chamado `replica1` (seção 5.6) |

> **Ninguém pediu senha?** O `replicador` tem senha, mas ela está no arquivo
> `~/.pgpass` do usuário `postgres` deste servidor. É assim que se faz em
> produção: senha num arquivo protegido (`chmod 600`), nunca digitada nem
> escrita na linha de comando.

Veja o que o `-R` fez:

<!-- rodar: bash-replica1 -->
```bash
tail -2 $PGDATA/postgresql.auto.conf
ls $PGDATA/*.signal
```

```
primary_conninfo = 'user=replicador passfile=''/var/lib/postgresql/.pgpass'' channel_binding=prefer host=primario port=5432 application_name=replica1 ...'
primary_slot_name = 'replica1'
/var/lib/postgresql/data/standby.signal
```

* **`primary_conninfo`**: como chegar no primário.
* **`primary_slot_name`**: qual slot usar lá.
* **`standby.signal`**: o arquivo que diz "ligue como **réplica**". Compare
  com o `recovery.signal` da etapa 4: aquele mandava recuperar até um ponto e
  parar; este manda recuperar **para sempre**.

Saia (`exit`) e ligue a réplica.

🖥️ **No seu terminal:**

<!-- rodar: shell -->
```bash
make reiniciar n=replica1
make status
```

```
NÓ           SITUAÇÃO               PAPEL        TL  LSN          LÊ DE      RÉPLICAS PG
primario     no ar                  primário     1   0/12000000   -          1        17
replica1     no ar                  réplica      1   0/12000000   primario   0        17
replica2     esperando dados
restauracao  no ar                  primário     2   0/F0BBD98    -          0        17
logico       no ar                  primário     1   0/1BEFEF0    -          0        18
```

O `replica1` é **réplica**, lê do `primario` e está no **mesmo LSN**. O
`primario` mostra **1** réplica conectada.

---

## 5.3 Olhando dos dois lados

Do lado do primário, cada réplica conectada é uma linha em
`pg_stat_replication`:

🐘 **No psql do `primario`:**

<!-- rodar: primario -->
```sql
\x on
SELECT application_name, client_addr, state, sent_lsn, write_lsn, flush_lsn,
       replay_lsn, write_lag, flush_lag, replay_lag, sync_state
FROM pg_stat_replication;
\x off
```

```
Expanded display is on.
-[ RECORD 1 ]----+----------------
application_name | replica1
client_addr      | 172.21.0.6
state            | streaming
sent_lsn         | 0/12000000
write_lsn        | 0/12000000
flush_lsn        | 0/12000000
replay_lsn       | 0/12000000
write_lag        | 00:00:00.000093
flush_lag        | 00:00:00.000093
replay_lag       | 00:00:00.000093
sync_state       | async

Expanded display is off.
```

(`\x on` mostra cada coluna numa linha: bom para tabelas largas.)

As quatro colunas de LSN são as quatro etapas da viagem de cada pedaço de WAL:

| Coluna | O WAL foi... | Se o primário cair agora, esse WAL... |
|---|---|---|
| `sent_lsn` | **enviado** pela rede | pode não ter chegado |
| `write_lsn` | **recebido** pela réplica (na memória do sistema operacional) | se perde se a réplica também cair |
| `flush_lsn` | **gravado no disco** da réplica | está seguro na réplica |
| `replay_lsn` | **reaplicado**: já aparece numa consulta na réplica | está seguro e visível |

E **`sync_state = async`**: o primário **não espera** nenhuma dessas etapas
para responder COMMIT. Guarde isso para a etapa 6.

Do lado da réplica:

🐘 **No psql do `replica1`** (`make psql n=replica1`):

<!-- rodar: replica1 -->
```sql
SELECT pg_is_in_recovery();

SELECT status, sender_host, slot_name, received_tli, latest_end_lsn
FROM pg_stat_wal_receiver;
```

```
 pg_is_in_recovery
-------------------
 t
(1 row)

  status   | sender_host | slot_name | received_tli | latest_end_lsn
-----------+-------------+-----------+--------------+----------------
 streaming | primario    | replica1  |            1 | 0/12000000
(1 row)
```

`pg_is_in_recovery() = t`: para o PostgreSQL, uma réplica é um servidor
**eternamente em recuperação**.

### Teste de fogo

🐘 **No psql do `primario`:**

<!-- rodar: primario -->
```sql
CREATE TABLE teste_replicacao (
    id         serial PRIMARY KEY,
    modo       text NOT NULL,
    criado_em  timestamptz DEFAULT now()
);
INSERT INTO teste_replicacao (modo) VALUES ('assincrono');
```

🐘 **No psql do `replica1`:**

<!-- rodar: replica1 -->
```sql
SELECT * FROM teste_replicacao;
```

```
 id |    modo    |          criado_em
----+------------+-------------------------------
  1 | assincrono | 2026-10-19 13:17:31.206893-03
(1 row)
```

A tabela e a linha chegaram: a replicação física copia **tudo**, inclusive o
`CREATE TABLE`. Agora tente escrever na réplica:

<!-- rodar: replica1 falha-esperada -->
```sql
INSERT INTO teste_replicacao (modo) VALUES ('escrevendo na replica');
```

```
ERROR:  cannot execute INSERT in a read-only transaction
```

Uma réplica física é **somente leitura**. Isso já tem utilidade: relatórios
pesados e consultas de BI podem rodar nela, sem pesar no primário.

---

## 5.4 A segunda réplica

Mesmo caminho, outro nome.

🖥️ **No seu terminal:**

```bash
make bash n=replica2
```

📦 **No terminal do `replica2`:**

<!-- rodar: bash-replica2 -->
```bash
pg_basebackup -h primario -U replicador -D $PGDATA \
  -d "application_name=replica2" -R -Xs -C -S replica2 -P
```

Saia (`exit`) e ligue.

🖥️ **No seu terminal:**

<!-- rodar: shell -->
```bash
make reiniciar n=replica2
make status
```

```
NÓ           SITUAÇÃO               PAPEL        TL  LSN          LÊ DE      RÉPLICAS PG
primario     no ar                  primário     1   0/14000000   -          2        17
replica1     no ar                  réplica      1   0/14000000   primario   0        17
replica2     no ar                  réplica      1   0/14000000   primario   0        17
restauracao  no ar                  primário     2   0/F0BBD98    -          0        17
logico       no ar                  primário     1   0/1BEFEF0    -          0        18
```

Duas réplicas, mesmo LSN.

---

## 5.5 Vendo o atraso

"Assíncrono" quer dizer que a réplica pode estar **atrasada**. Normalmente o
atraso é de milissegundos, rápido demais para ver. Então vamos congelar a
réplica: o `pg_wal_replay_pause()` faz a `replica1` continuar **recebendo** o
WAL, mas parar de **reaplicar**.

🐘 **No psql do `replica1`:**

<!-- rodar: replica1 -->
```sql
SELECT pg_wal_replay_pause();
```

🐘 **No psql do `primario`:**

<!-- rodar: primario -->
```sql
INSERT INTO teste_replicacao (modo) VALUES ('assincrono, replica1 congelada');
SELECT pg_sleep(1);

SELECT application_name, sent_lsn, flush_lsn, replay_lsn,
       pg_size_pretty(pg_wal_lsn_diff(sent_lsn, replay_lsn)) AS atraso
FROM pg_stat_replication ORDER BY 1;
```

```
 application_name |  sent_lsn  | flush_lsn  | replay_lsn |  atraso
------------------+------------+------------+------------+-----------
 replica1         | 0/14000210 | 0/14000210 | 0/14000000 | 528 bytes
 replica2         | 0/14000210 | 0/14000210 | 0/14000210 | 0 bytes
(2 rows)
```

O primário deu COMMIT na hora, sem esperar ninguém. (O `pg_sleep(1)` só dá
tempo de o WAL viajar e de as réplicas avisarem o primário: são
milissegundos, mas uma consulta colada logo em seguida pode ser mais rápida
que eles.) A `replica1` **gravou** o
WAL no disco (`flush_lsn` em dia), mas não reaplicou (`replay_lsn` atrasado):

🐘 **No psql do `replica1`:**

<!-- rodar: replica1 -->
```sql
SELECT id, modo FROM teste_replicacao;

SELECT pg_wal_replay_resume();
SELECT pg_sleep(1);

SELECT id, modo FROM teste_replicacao;
```

```
 id |    modo
----+------------
  1 | assincrono
(1 row)
...
 id |              modo
----+--------------------------------
  1 | assincrono
  2 | assincrono, replica1 congelada
(2 rows)
```

Congelada, ela não mostrava a linha nova. Descongelada, mostrou na hora.

> Agora imagine que a `replica1` atende os relatórios da diretoria e está
> atrasada: o relatório mostra um número velho. E se o primário morresse
> antes de enviar um WAL que a réplica ainda nem **recebeu**, essa venda se
> perderia. É o preço do assíncrono, e o assunto da etapa 6.

Para ver o atraso ao vivo com o simulador ligado, rode `make carga t=60` num
terminal e, no psql do `primario`, a consulta acima seguida de `\watch 1`
(ela se repete a cada segundo; pare com `Ctrl+C`).

---

## 5.6 Replication slots

O `-C -S` criou um **slot** para cada réplica. Para que serve?

O primário recicla os segmentos de WAL depois do checkpoint. Se uma réplica
ficar desligada por uma hora, quando ela voltar o WAL de que precisa **pode já
ter sido apagado**, e ela nunca mais alcança o primário: é preciso clonar de
novo. O slot é uma promessa do primário: "**não apago WAL que a `replica1`
ainda não recebeu**".

Desligue a `replica1` e venda um pouco:

🖥️ **No seu terminal:**

<!-- rodar: shell -->
```bash
make parar n=replica1
make carga t=10
```

🐘 **No psql do `primario`:**

<!-- rodar: primario -->
```sql
SELECT slot_name, active, wal_status,
       pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) AS wal_retido
FROM pg_replication_slots;
```

```
 slot_name | active | wal_status | wal_retido
-----------+--------+------------+------------
 replica1  | f      | reserved   | 625 kB
 replica2  | t      | reserved   | 0 bytes
(2 rows)
```

O slot da `replica1` está inativo e **segurando** o WAL desde que ela caiu.
O seu número pode ser bem maior, uns 17 MB: a conta é feita pela posição no
WAL e, se o `archive_timeout` da etapa 4 fechou um segmento nesse meio
tempo, o salto até o segmento seguinte (16 MB) entra na conta.
Ligue-a de novo:

🖥️ **No seu terminal:**

<!-- rodar: shell -->
```bash
make ligar n=replica1
sleep 2
```

🐘 **No psql do `primario`:**

<!-- rodar: primario -->
```sql
SELECT slot_name, active,
       pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) AS wal_retido
FROM pg_replication_slots;
```

```
 slot_name | active | wal_retido
-----------+--------+------------
 replica1  | t      | 0 bytes
 replica2  | t      | 0 bytes
(2 rows)
```

Ela pegou o WAL guardado, alcançou o primário e o slot liberou o espaço.

> ⚠️ **O lado perigoso do slot:** se uma réplica morrer **para sempre** e
> ninguém apagar o slot dela, o primário guarda WAL para sempre, até encher o
> disco e **parar a produção**. Duas defesas: monitorar o `wal_retido` e
> configurar `max_slot_wal_keep_size` (um teto: passou dele, o slot é
> invalidado e a réplica terá de ser clonada de novo). Réplica que não volta
> mais: `SELECT pg_drop_replication_slot('nome')`.

---

## 5.7 Réplica não é backup

Uma última experiência, a mais importante desta etapa. Lembra da tabela
`teste_wal`, da etapa 1? Ela está nas duas réplicas:

🐘 **No psql do `replica2`** (`make psql n=replica2`):

<!-- rodar: replica2 -->
```sql
SELECT count(*) FROM teste_wal;
```

```
 count
-------
     3
(1 row)
```

Agora apague-a no primário:

🐘 **No psql do `primario`:**

<!-- rodar: primario -->
```sql
DROP TABLE teste_wal;
```

🐘 **No psql do `replica2`:**

<!-- rodar: replica2 falha-esperada -->
```sql
SELECT count(*) FROM teste_wal;
```

```
ERROR:  relation "teste_wal" does not exist
```

Sumiu das duas réplicas em milissegundos. A réplica copia **fielmente** tudo o
que o primário faz, inclusive o erro. Ela protege contra a **queda do
servidor**, nunca contra o **erro humano**. Para isso existe o que você fez
nas etapas 2 a 4. Um cluster de verdade tem **as duas coisas**.

---

## 5.8 O novo quadro

| Cenário | Com PITR (etapa 4) | Com réplicas |
|---|---|---|
| O servidor morre | restaurar backup + WAL: minutos a horas | **promover uma réplica: segundos** (etapa 7) |
| Quanto se perde (RPO) | até 60 s (`archive_timeout`) | o atraso da réplica: normalmente milissegundos, **mas não zero** |
| Alguém apaga uma tabela | volta ao segundo anterior | **a réplica apaga junto** |

---

## ✔️ Confira

🖥️ **No seu terminal:**

<!-- rodar: shell -->
```bash
make conferir e=5
```

```
Conferindo a etapa 5 - Replicação assíncrona

  ✅ usuário replicador existe, com REPLICATION e sem superusuário
  ✅ pg_hba.conf libera a replicação para o replicador
  ✅ replica1 é réplica e está recebendo o WAL do primario (streaming)
  ✅ replica2 é réplica e está recebendo o WAL do primario (streaming)
  ✅ slots replica1 e replica2 ativos no primario
  ✅ teste_replicacao igual nos três nós (2 linhas)

✅ Etapa 5 conferida.
```

---

# ➡️ Continue em [6. Replicação síncrona](../06_replicacao_sincrona/README.md)
