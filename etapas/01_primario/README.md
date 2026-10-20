# 1️⃣ Conhecer o primário

> ⬅️ [README principal](../../README.md) · Etapa 1 de 10

Você acaba de ser contratado como Database Engineer da Liga Sudoers. Antes de
mexer em qualquer coisa, um bom DBE faz o que um médico faz: **examina o
paciente**. Nesta etapa você não muda nada de importante. Você descobre:

* onde o PostgreSQL guarda os dados, em disco;
* como ele está configurado, e quais configurações exigem reiniciar;
* o que é o **WAL**, a peça que sustenta tudo o que vem depois: backup,
  PITR e replicação;
* o que acontece quando o servidor cai, e o que **não** tem conserto hoje.

Ao final você vai preencher o diagnóstico que o CTO pediu: **quanto dado a
empresa perde, e quanto tempo fica fora**, se der problema hoje.

---

## 1.1 Entrando no banco

🖥️ **No seu terminal:**

```bash
make psql n=primario
```

O prompt muda para `liga_sudoers=#`. Você está dentro do banco de produção.

🐘 **No psql do `primario`:**

<!-- rodar: primario -->
```sql
\dt+
```

```
                                         List of relations
 Schema |       Name        | Type  |  Owner  | Persistence | Access method |  Size   | Description
--------+-------------------+-------+---------+-------------+---------------+---------+-------------
 public | auditoria_pedidos | table | sudoers | permanent   | heap          | 8464 kB |
 public | categorias        | table | sudoers | permanent   | heap          | 40 kB   |
 public | itens_pedidos     | table | sudoers | permanent   | heap          | 16 MB   |
 public | pedidos           | table | sudoers | permanent   | heap          | 7952 kB |
 public | pessoas           | table | sudoers | permanent   | heap          | 72 kB   |
 public | produtos          | table | sudoers | permanent   | heap          | 56 kB   |
(6 rows)
```

São 6 tabelas simples (cadastro, catálogo e vendas). O que importa aqui é o
volume: 18 meses de vendas.

<!-- rodar: primario -->
```sql
SELECT (SELECT count(*) FROM pessoas)           AS pessoas,
       (SELECT count(*) FROM produtos)          AS produtos,
       (SELECT count(*) FROM pedidos)           AS pedidos,
       (SELECT count(*) FROM itens_pedidos)     AS itens,
       pg_size_pretty(pg_database_size('liga_sudoers')) AS tamanho;
```

```
 pessoas | produtos | pedidos | itens  | tamanho
---------+----------+---------+--------+---------
     500 |      200 |  100000 | 248964 | 50 MB
(1 row)
```

> Se você já rodou `make carga` alguma vez, terá mais pedidos do que isso.
> Tudo bem.

---

## 1.2 Onde o dado mora

Um banco de dados, no fim das contas, é **um monte de arquivos numa pasta**.
Essa pasta se chama **diretório de dados**, e a variável de ambiente que
aponta para ela é a `PGDATA`.

Abra um **segundo terminal** na pasta do repositório e entre no servidor:

🖥️ **No seu terminal:**

```bash
make bash n=primario
```

Agora você está dentro do servidor, como o usuário `postgres` (o dono dos
arquivos). É como entrar por SSH numa máquina de produção.

📦 **No terminal do `primario`:**

<!-- rodar: bash-primario -->
```bash
echo $PGDATA
ls $PGDATA
```

```
/var/lib/postgresql/data
base          pg_dynshmem    pg_multixact  pg_snapshots  pg_tblspc    pg_xact
global        pg_hba.conf    pg_notify     pg_stat       pg_twophase  postgresql.auto.conf
pg_commit_ts  pg_ident.conf  pg_replslot   pg_stat_tmp   PG_VERSION   postgresql.conf
pg_logical    pg_serial      pg_subtrans   pg_wal        postmaster.opts  postmaster.pid
```

As peças que importam nesta disciplina:

| Pasta / arquivo | O que guarda |
|---|---|
| `base/` | as tabelas e os índices, um arquivo para cada |
| `pg_wal/` | o **WAL**: o diário de tudo o que mudou (já já) |
| `postgresql.conf` | a configuração escrita à mão |
| `postgresql.auto.conf` | a configuração alterada com `ALTER SYSTEM` (você vai usar muito) |
| `pg_hba.conf` | **quem** pode conectar, **de onde** e **como** (a "portaria") |
| `pg_replslot/` | os *replication slots* (etapa 5) |

Quanto espaço cada parte ocupa (o `base/` tem mais que os 50 MB do banco
porque guarda também os bancos internos `postgres`, `template0` e `template1`):

<!-- rodar: bash-primario -->
```bash
du -sh $PGDATA/base $PGDATA/pg_wal
```

```
72M	/var/lib/postgresql/data/base
97M	/var/lib/postgresql/data/pg_wal
```

E qual arquivo é a tabela `pedidos`:

<!-- rodar: bash-primario -->
```bash
ARQUIVO=$(psql -U sudoers -d liga_sudoers -Atc "SELECT pg_relation_filepath('pedidos')")
echo $ARQUIVO
ls -lh $PGDATA/$ARQUIVO
```

```
base/16384/16417
-rw------- 1 postgres postgres 7.8M Oct 19 13:16 /var/lib/postgresql/data/base/16384/16417
```

A tabela `pedidos` **é** esse arquivo. `16384` é o número do banco
`liga_sudoers` e `16417` é o número da tabela (os seus podem ser outros).
Guarde a ideia: **copiar o banco é copiar arquivos** — mas, como você vai
ver, não com o banco ligado e não de qualquer jeito.

> 🚫 **Nunca** mexa nesses arquivos com o banco ligado: nem `cp`, nem `rm`,
> nem editor de texto. Quem cuida deles é o PostgreSQL.

---

## 1.3 Como ele está configurado

De volta ao 🐘 **psql do `primario`:**

<!-- rodar: primario -->
```sql
SELECT name, setting, unit, context
FROM pg_settings
WHERE name IN ('wal_level', 'archive_mode', 'max_wal_senders', 'synchronous_commit',
               'synchronous_standby_names', 'data_checksums', 'max_wal_size',
               'checkpoint_timeout', 'shared_buffers', 'hot_standby')
ORDER BY name;
```

```
           name            | setting | unit |  context
---------------------------+---------+------+------------
 archive_mode              | off     |      | postmaster
 checkpoint_timeout        | 300     | s    | sighup
 data_checksums            | on      |      | internal
 hot_standby               | on      |      | postmaster
 max_wal_senders           | 10      |      | postmaster
 max_wal_size              | 1024    | MB   | sighup
 shared_buffers            | 16384   | 8kB  | postmaster
 synchronous_commit        | on      |      | user
 synchronous_standby_names |         |      | sighup
 wal_level                 | replica |      | postmaster
(10 rows)
```

A coluna mais importante é a **`context`**. Ela diz o que custa mudar cada
configuração:

| `context` | Para valer, precisa... | Em produção isso significa... |
|---|---|---|
| `postmaster` | **reiniciar** o servidor | uma janela de manutenção (a loja fica fora alguns segundos) |
| `sighup` | só **recarregar** (`SELECT pg_reload_conf()`) | nada: ninguém percebe |
| `user` | nada: cada sessão pode mudar a sua (`SET ...`) | cada transação escolhe |
| `internal` | não dá para mudar depois de criado o banco | decida certo no `initdb` |

Repare em três coisas que você vai mexer:

* **`archive_mode = off`**: o WAL **não está sendo guardado**. É por isso que
  hoje não existe PITR. Mudar exige reiniciar (etapa 4).
* **`wal_level = replica`**: o WAL tem informação suficiente para réplicas
  físicas, mas não para replicação lógica (etapa 8).
* **`data_checksums = on`**: cada página de dados tem um "dígito verificador".
  Isso detecta corrupção no disco e é pré-requisito do `pg_rewind` (etapa 7).
  É `internal`: ou se liga na criação do banco, ou nunca mais. (A partir do
  PostgreSQL 18 ele já vem ligado por padrão.)

---

## 1.4 O WAL: o diário do banco

Esta é a ideia mais importante da disciplina. Leia com calma.

Quando você faz um `INSERT`, o PostgreSQL **não** corre para gravar a linha
no arquivo da tabela. Gravar no meio de um arquivo grande é lento e, se a
energia cair no meio, o arquivo fica pela metade. Em vez disso, ele:

1. escreve **num diário** o que vai fazer: "inseri a linha X na página Y da
   tabela Z". Esse diário só cresce no final, o que é rápido e seguro;
2. garante que esse registro chegou ao disco (*fsync*);
3. só então responde **COMMIT** para você;
4. a tabela em si é atualizada depois, com calma, na memória, e vai para o
   disco de tempos em tempos (no **checkpoint**).

Esse diário é o **WAL** — *Write-Ahead Log*, "registro escrito antes". Se o
servidor cair entre o passo 3 e o 4, nada se perde: ao religar, o PostgreSQL
**relê o WAL e refaz** o que faltava.

Cada posição no WAL tem um endereço, o **LSN** (*Log Sequence Number*). É um
número que só cresce, escrito em hexadecimal: `0/705E348`. Veja-o andar:

🐘 **No psql do `primario`:**

<!-- rodar: primario -->
```sql
CREATE TABLE teste_wal (id serial PRIMARY KEY, texto text);

SELECT pg_current_wal_lsn() AS antes \gset

INSERT INTO teste_wal (texto) VALUES ('minha primeira linha no WAL');

SELECT :'antes'                                          AS lsn_antes,
       pg_current_wal_lsn()                              AS lsn_depois,
       pg_wal_lsn_diff(pg_current_wal_lsn(), :'antes')   AS bytes_de_wal;
```

```
 lsn_antes | lsn_depois | bytes_de_wal
-----------+------------+--------------
 0/7012090 | 0/7012250  |          448
(1 row)
```

Um `INSERT` de uma linha gerou umas centenas de bytes de WAL: a linha em si,
a entrada no índice da chave primária e o registro do `COMMIT`. (O `\gset`
guarda o resultado de uma consulta numa variável do psql: `:'antes'`.)

O WAL fica em arquivos de **16 MB** cada, chamados **segmentos** (o servidor
já deixa alguns criados de antemão, para não perder tempo criando na hora):

<!-- rodar: primario -->
```sql
SELECT pg_walfile_name(pg_current_wal_lsn()) AS segmento_atual;

SELECT name, pg_size_pretty(size) AS tamanho FROM pg_ls_waldir() ORDER BY name LIMIT 5;
```

```
      segmento_atual
--------------------------
 000000010000000000000007
(1 row)

           name           | tamanho
--------------------------+---------
 000000010000000000000006 | 16 MB
 000000010000000000000007 | 16 MB
 000000010000000000000008 | 16 MB
 000000010000000000000009 | 16 MB
 00000001000000000000000A | 16 MB
(5 rows)
```

Leia o nome do segmento em três pedaços de 8 dígitos:
`00000001` `00000000` `00000007`. O primeiro é a **timeline** (a "linha do
tempo" do banco: guarde isso para a etapa 4). Os outros dois são a posição.

### Lendo o WAL por dentro

O `pg_waldump` traduz o WAL para texto. Grave uma linha e leia exatamente o
que ela gerou:

📦 **No terminal do `primario`:**

<!-- rodar: bash-primario -->
```bash
INICIO=$(psql -U sudoers -d liga_sudoers -Atc "SELECT pg_current_wal_insert_lsn()")
psql -U sudoers -d liga_sudoers -c "INSERT INTO teste_wal (texto) VALUES ('lendo o WAL por dentro')"
FIM=$(psql -U sudoers -d liga_sudoers -Atc "SELECT pg_current_wal_insert_lsn()")
pg_waldump -p $PGDATA/pg_wal -s $INICIO -e $FIM
```

```
INSERT 0 1
rmgr: Heap        len (rec/tot):     82/    82, tx:       1524, lsn: 0/07012250, prev 0/07012228, desc: INSERT off: 2, flags: 0x00, blkref #0: rel 1663/16384/16483 blk 0
rmgr: Btree       len (rec/tot):     64/    64, tx:       1524, lsn: 0/070122A8, prev 0/07012250, desc: INSERT_LEAF off: 2, blkref #0: rel 1663/16384/16489 blk 1
rmgr: Transaction len (rec/tot):     34/    34, tx:       1524, lsn: 0/070122E8, prev 0/070122A8, desc: COMMIT 2026-10-19 13:16:07.021023 -03
```

Três registros, na ordem: **Heap INSERT** (a linha na tabela), **Btree
INSERT_LEAF** (a linha no índice da chave primária) e **Transaction COMMIT**.
Todos com o mesmo número de transação (`tx`).

Guarde esta imagem. Tudo o que vem pela frente é **fazer alguma coisa com
esse diário**:

| Etapa | O que se faz com o WAL |
|---|---|
| 3 | o backup físico copia os arquivos **e** o WAL gerado durante a cópia |
| 4 | guardar **todo** o WAL permite reaplicá-lo até um segundo qualquer (PITR) |
| 5 e 6 | mandar o WAL, ao vivo, para outro servidor: isso é a replicação física |
| 8 | traduzir o WAL em "inseriu a linha X na tabela Y": isso é a replicação lógica |

---

## 1.5 O servidor caiu. E agora?

Vamos simular uma queda de energia: o `docker kill` mata o PostgreSQL na hora,
sem dar chance de ele fechar nada direito.

Primeiro, grave uma linha e veja o COMMIT:

🐘 **No psql do `primario`:**

<!-- rodar: primario -->
```sql
INSERT INTO teste_wal (texto) VALUES ('gravada um instante antes da queda');
```

Agora derrube o servidor.

🖥️ **No seu terminal** (o primeiro, fora do container):

<!-- rodar: shell -->
```bash
docker kill dbe_primario
make status
```

```
NÓ           SITUAÇÃO               PAPEL        TL  LSN          LÊ DE      RÉPLICAS PG
primario     desligado
...
```

O seu psql e o seu terminal do `primario` caíram junto: é o que acontece com
quem está conectado num servidor que morre. Nas janelas deles aparece algo
como `make: *** [Makefile:68: psql] Error 137`: não é erro seu, é o `make`
avisando que o container foi morto. Ligue de novo e leia o log:

<!-- rodar: shell -->
```bash
make ligar n=primario
docker logs dbe_primario 2>&1 | grep -E "not properly shut down|redo (starts|done)|ready to accept" | tail -4
```

```
docker start dbe_primario
dbe_primario
  ✅ primario pronto
LOG:  database system was not properly shut down; automatic recovery in progress
LOG:  redo starts at 0/6FC3360
LOG:  redo done at 0/70123B0 system usage: CPU: user: 0.00 s, system: 0.00 s, elapsed: 0.00 s
LOG:  database system is ready to accept connections
```

Leia linha a linha: "não fui desligado direito, recuperação automática" →
"refazendo (*redo*) a partir do LSN tal" → "fim do WAL" → "pronto". O
PostgreSQL releu o WAL desde o último checkpoint e refez tudo.

Entre de novo (`make psql n=primario`) e confira:

<!-- rodar: primario -->
```sql
SELECT * FROM teste_wal;
```

```
 id |               texto
----+------------------------------------
  1 | minha primeira linha no WAL
  2 | lendo o WAL por dentro
  3 | gravada um instante antes da queda
(3 rows)
```

**Nada se perdeu.** Toda transação que recebeu COMMIT sobrevive a uma queda
de energia. Esse é o "D" do ACID, a **durabilidade**, e quem garante é o WAL.

### O que o WAL **não** resolve

O WAL mora no **mesmo disco** que os dados. Se a queda for de energia, ótimo.
Mas e se:

* o **disco** morrer? Vão-se os dados **e** o WAL.
* alguém rodar `DROP TABLE pedidos`? O WAL registra fielmente o `DROP`, e a
  recuperação automática refaz o `DROP`.
* o **servidor** pegar fogo? Não há outro para assumir.

Para isso existem backup, PITR e replicação: o resto da trilha.

---

## 1.6 Um dia de vendas

O `make carga` simula clientes comprando na loja. Cada venda grava um pedido
e o seu item. Rode 20 segundos de vendas:

🖥️ **No seu terminal:**

<!-- rodar: shell -->
```bash
make carga t=20
```

```
Simulando vendas em primario por 20s, 100 vendas/s...
progress: 5.0 s, 99.4 tps, lat 0.862 ms stddev 0.228, 0 failed, lag 0.093 ms
progress: 10.0 s, 100.4 tps, lat 1.200 ms stddev 0.361, 0 failed, lag 0.109 ms
progress: 15.0 s, 98.4 tps, lat 1.149 ms stddev 0.368, 0 failed, lag 0.105 ms
number of transactions actually processed: 1981
latency average = 1.017 ms
tps = 99.209822 (without initial connection time)
```

`tps` são as transações (vendas) por segundo e `lat` é quanto cada uma levou.
O padrão é 100 vendas por segundo; `make carga r=0` tira o limite e mostra
quanto o servidor aguenta.

Quanto WAL essas vendas geraram? A view `pg_stat_wal` conta o WAL desde a
última vez que as estatísticas foram zeradas, e elas **são zeradas numa
queda** como a da seção 1.5. Ou seja: o número abaixo é, praticamente, só o
das vendas que você acabou de simular.

🐘 **No psql do `primario`:**

<!-- rodar: primario -->
```sql
SELECT wal_records, pg_size_pretty(wal_bytes) AS wal_gerado FROM pg_stat_wal;
```

```
 wal_records | wal_gerado
-------------+------------
       15936 | 1220 kB
(1 row)
```

Umas 2.000 vendas geraram 1,2 MB de WAL: cerca de **600 bytes por venda**.
Faça a conta que um DBE faz para dimensionar o storage de backup: a 100
vendas por segundo, são 8,6 milhões de vendas por dia, ou uns **5 GB de WAL
por dia**, cem vezes o tamanho do banco hoje. O WAL registra **cada
mudança**, e não só o estado final. Guarde esse número para a etapa 4.

---

## 1.7 O diagnóstico

Com o que você viu, preencha o diagnóstico que o CTO pediu:

| Cenário | Hoje, quanto dado se perde? (RPO) | Quanto tempo fora? (RTO) |
|---|---|---|
| Queda de energia | nada (o WAL refaz) | o tempo de religar: segundos |
| Alguém apaga uma tabela | **a tabela inteira** | **para sempre** |
| O disco morre | **o banco inteiro** | **para sempre** |
| O servidor pega fogo | **o banco inteiro** | **para sempre** |

Três "para sempre". É esse o quadro que você vai mudar até a etapa 9.

---

## ✔️ Confira

Nesta etapa você só olhou. A prova é saber responder:

* [ ] O que é o `PGDATA` e o que tem em `base/` e em `pg_wal/`?
* [ ] Qual a diferença entre uma configuração `postmaster` e uma `sighup`?
* [ ] Por que o PostgreSQL escreve no WAL **antes** de escrever na tabela?
* [ ] Por que uma queda de energia não perde dado, mas um disco queimado perde tudo?

Saia dos dois terminais (`\q` no psql e `exit` no terminal do `primario`).

---

# ➡️ Continue em [2. Backup lógico](../02_backup_logico/README.md)
