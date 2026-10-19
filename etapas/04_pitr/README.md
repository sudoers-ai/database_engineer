# 4️⃣ PITR: voltando a um segundo qualquer

> ⬅️ Anterior: [3. Backup físico](../03_backup_fisico/README.md) · [README principal](../../README.md) · Etapa 4 de 10

> **A pergunta da diretoria:** "Um `UPDATE` errado rodou às 14h03. Dá para
> voltar às 14h02?"

Os dois backups que você já fez voltam ao **momento do backup**. Nesta etapa
você monta o que os bancos de verdade usam: um backup físico **mais** a cópia
contínua de todo o WAL gerado depois dele. Com as duas peças você consegue
reconstruir o banco em **qualquer instante**, até o último segundo. Isso se
chama **PITR** (*Point-In-Time Recovery*).

E você vai precisar: um deploy da Black Friday vai zerar o preço de todos os
produtos, e a loja vai continuar vendendo.

---

## 4.1 A ideia

```
  backup físico                                                     agora
       │                                                              │
       ▼        WAL arquivado, segmento por segmento                  ▼
  ─────●════╤════╤════╤════╤════╤════╤════╤════╤════╤════╤════╤═══════●──►
            seg  seg  seg  seg  seg  ... │ ...
                                         │
                       "volte para AQUI" ┘   (um LSN, um horário, um nome)
```

1. Você tem um **backup físico** (o ponto de partida).
2. Todo segmento de WAL que o servidor fecha é **copiado** para o storage de
   backup. Isso é o **arquivamento de WAL** (*WAL archiving*).
3. Para restaurar, você liga o backup e manda o servidor reaplicar o WAL
   arquivado **até um ponto que você escolhe**, e parar ali.

Na etapa 1 você viu que o `archive_mode` está **desligado**. Hoje, cada
segmento de WAL é reciclado depois do checkpoint e some para sempre.

---

## 4.2 Ligando o arquivamento

O PostgreSQL não sabe copiar arquivos para o seu storage: ele chama um
**comando seu** para cada segmento pronto. Esse é o `archive_command`.

Crie a pasta do arquivo de WAL.

🖥️ **No seu terminal:**

```bash
make bash n=primario
```

📦 **No terminal do `primario`:**

<!-- rodar: bash-primario -->
```bash
mkdir -p /backup/wal
ls -la /backup/wal
```

```
total 8
drwxr-xr-x 2 postgres postgres 4096 Oct 19 13:16 .
drwxr-x--- 5 postgres postgres 4096 Oct 19 13:16 ..
```

Vazia, por enquanto. Agora configure.

🐘 **No psql do `primario`** (`make psql n=primario`):

<!-- rodar: primario -->
```sql
ALTER SYSTEM SET archive_mode = 'on';
ALTER SYSTEM SET archive_command = 'test ! -f /backup/wal/%f && cp %p /backup/wal/%f || cmp -s %p /backup/wal/%f';
ALTER SYSTEM SET archive_timeout = '60s';
```

```
ALTER SYSTEM
ALTER SYSTEM
ALTER SYSTEM
```

Linha a linha:

* **`archive_mode = 'on'`**: liga o arquivamento. É `postmaster`: só vale
  depois de **reiniciar**.
* **`archive_command`**: o comando que o servidor roda para cada segmento.
  `%p` é o caminho do segmento dentro do `pg_wal/` e `%f` é só o nome do
  arquivo. Leia em duas partes:
  * `test ! -f ... && cp ...`: se o arquivo **ainda não existe** no
    storage, copie. Nunca sobrescreva um segmento que já está lá.
  * `|| cmp -s ...`: se ele **já existe**, responda sucesso só se for
    **idêntico** ao que se quer arquivar. Parece exagero, mas é o que salva a
    etapa 7: depois de um failover, um servidor pode tentar arquivar de novo
    um segmento que já foi arquivado. Sem o `cmp`, o arquivamento ficaria
    travado ali para sempre; com ele, segmento igual passa, e segmento
    **diferente** com o mesmo nome continua falhando (aí, sim, é um incidente
    para um humano olhar).

  Se o comando falhar, o PostgreSQL **não apaga** o segmento e tenta de novo:
  ele só recicla um segmento depois que o `archive_command` devolve sucesso.
* **`archive_timeout = '60s'`**: um segmento só fica "pronto" quando enche
  (16 MB). Numa madrugada de pouco movimento, isso pode levar horas, e esse
  WAL ainda não arquivado se perde se o disco morrer. Com o timeout, o
  servidor fecha o segmento a cada 60 segundos, mesmo pela metade. Esse
  número é, na prática, o seu **RPO**.

> O `ALTER SYSTEM` grava no arquivo `postgresql.auto.conf`, e não no
> `postgresql.conf`. Quem quiser saber o que foi alterado num servidor olha
> primeiro para ele.

Reinicie para valer.

🖥️ **No seu terminal** (fora do container):

<!-- rodar: shell -->
```bash
make reiniciar n=primario
```

Entre de novo no psql (o reinício derrubou a conexão) e confira:

🐘 **No psql do `primario`:**

<!-- rodar: primario -->
```sql
SHOW archive_mode;

SELECT pg_switch_wal();
SELECT pg_sleep(2);

SELECT archived_count, last_archived_wal, failed_count FROM pg_stat_archiver;
```

```
 archive_mode
--------------
 on
(1 row)

 pg_switch_wal
---------------
 0/D002640
(1 row)
...
 archived_count |    last_archived_wal     | failed_count
----------------+--------------------------+--------------
              1 | 00000001000000000000000D |            0
(1 row)
```

O `pg_switch_wal()` força o fechamento do segmento atual. Ele foi arquivado
e `failed_count = 0`. A view `pg_stat_archiver` é o que se monitora em
produção: **arquivamento falhando é incidente**, porque o `pg_wal/` começa a
encher até o disco acabar.

---

## 4.3 Um backup base novo

O backup da etapa 3 foi feito **antes** do arquivamento existir: o WAL entre
ele e agora se perdeu. O PITR precisa de um backup feito com o arquivamento
já ligado.

📦 **No terminal do `primario`:**

<!-- rodar: bash-primario -->
```bash
pg_basebackup -U sudoers -D /backup/base/pitr -Fp -Xs -c fast -P
ls /backup/wal
```

```
75025/75025 kB (100%), 1/1 tablespace
00000001000000000000000D
00000001000000000000000E
00000001000000000000000E.00000028.backup
```

O arquivo `.backup` é um marcador: "um backup base começou aqui". A partir
deste ponto, **backup base + arquivo de WAL** formam a sua linha do tempo
completa.

---

## 4.4 Black Friday

A loja abre e vende normalmente.

🖥️ **No seu terminal:**

<!-- rodar: shell -->
```bash
make carga t=10
```

O time de desenvolvimento vai fazer o deploy da promoção. Antes de todo
deploy, a equipe segue uma boa prática: marca um **ponto de restauração**
com nome. É só uma etiqueta no WAL, de graça.

🐘 **No psql do `primario`:**

<!-- rodar: primario -->
```sql
SELECT count(*) AS pedidos FROM pedidos;
SELECT sum(valor_unit) AS soma_dos_precos FROM produtos;

SELECT pg_create_restore_point('antes_do_deploy');
```

```
 pedidos
---------
  103985
(1 row)

 soma_dos_precos
-----------------
       504547.61
(1 row)

 pg_create_restore_point
-------------------------
 0/F097E60
(1 row)
```

Anote a **soma dos preços** (`504547.61`). E então o deploy roda, com um bug:

<!-- rodar: primario -->
```sql
UPDATE produtos SET valor_unit = 0.01;
SELECT now() AS hora_do_bug;
```

```
UPDATE 200
          hora_do_bug
-------------------------------
 2026-10-19 13:17:00.368644-03
(1 row)
```

Todos os 200 produtos passaram a custar **um centavo**. E a loja continua no
ar.

🖥️ **No seu terminal:**

<!-- rodar: shell -->
```bash
make carga t=10
```

🐘 **No psql do `primario`:**

<!-- rodar: primario -->
```sql
SELECT count(*) AS vendas_a_um_centavo FROM itens_pedidos WHERE valor_total <= 0.03;
```

```
 vendas_a_um_centavo
---------------------
                1000
(1 row)
```

Mil vendas a preço de banana até alguém perceber.

---

## 4.5 Qual é o plano?

A tentação é "voltar o banco para antes do deploy". Pense no que isso faz: o
banco inteiro volta para `antes_do_deploy`, e as **mil vendas feitas depois**
somem. São clientes de verdade, que pagaram e receberam e-mail de
confirmação. Apagá-las é trocar um incidente por outro.

O que um DBE faz:

1. restaura o banco até `antes_do_deploy` **em outro servidor**, sem tocar
   na produção (que continua vendendo);
2. copia de lá **só o que o bug estragou**: os preços;
3. corrige a produção com esses preços.

A decisão sobre as mil vendas a um centavo (honrar, cancelar, oferecer
cupom) é do negócio. O seu trabalho é **não perder nada** e entregar a lista.

---

## 4.6 O WAL do desastre já foi arquivado?

O PITR só alcança o WAL que está **no arquivo**. O ponto `antes_do_deploy`
está num segmento que talvez ainda esteja aberto. Feche-o:

<!-- rodar: primario -->
```sql
SELECT pg_switch_wal();
SELECT pg_sleep(2);
SELECT last_archived_wal, failed_count FROM pg_stat_archiver;
```

```
...
    last_archived_wal     | failed_count
--------------------------+--------------
 00000001000000000000000F |            0
(1 row)
```

(Se você esperasse 60 segundos, o `archive_timeout` faria isso sozinho.)

---

## 4.7 Restaurando até o ponto escolhido

O nó `restauracao` ainda tem o servidor da etapa 3. Apague-o: ele vai receber
o backup novo.

🖥️ **No seu terminal:**

<!-- rodar: shell -->
```bash
make zerar n=restauracao
```

```
Apagando a pasta de dados de restauracao...
  ✅ restauracao está vazio, esperando dados.
```

Agora copie o backup base e diga ao servidor **até onde** reaplicar o WAL.

```bash
make bash n=restauracao
```

📦 **No terminal do `restauracao`:**

<!-- rodar: bash-restauracao -->
```bash
cp -a /backup/base/pitr/. $PGDATA/

cat >> $PGDATA/postgresql.auto.conf <<'EOF'
# --- restauracao point-in-time (etapa 4) ---
restore_command = 'cp /backup/wal/%f %p'
recovery_target_name = 'antes_do_deploy'
recovery_target_action = 'promote'
archive_mode = 'off'
EOF

touch $PGDATA/recovery.signal

tail -8 $PGDATA/postgresql.auto.conf
```

```
archive_mode = 'on'
archive_command = 'test ! -f /backup/wal/%f && cp %p /backup/wal/%f || cmp -s %p /backup/wal/%f'
archive_timeout = '60s'
# --- restauracao point-in-time (etapa 4) ---
restore_command = 'cp /backup/wal/%f %p'
recovery_target_name = 'antes_do_deploy'
recovery_target_action = 'promote'
archive_mode = 'off'
```

Cada linha conta:

| Configuração | O que faz |
|---|---|
| `restore_command` | o **inverso** do `archive_command`: como buscar um segmento no arquivo e colocar no `pg_wal/` |
| `recovery_target_name` | **até onde** ir: o ponto de restauração com esse nome |
| `recovery_target_action = 'promote'` | ao chegar lá, parar de reaplicar e virar um servidor normal |
| `archive_mode = 'off'` | ⚠️ **essencial**: o backup trouxe a configuração do `primario`, que arquiva em `/backup/wal`. Se o servidor restaurado também arquivar ali, ele **mistura o WAL dele com o da produção** e estraga o arquivo que você acabou de usar |
| `recovery.signal` | o arquivo vazio que diz "ligue em **modo de recuperação**" |

> Repare que `archive_mode` aparece duas vezes no arquivo. No
> `postgresql.auto.conf` (e no `postgresql.conf`) **vale a última
> ocorrência**.

Saia (`exit`) e ligue o servidor.

🖥️ **No seu terminal:**

<!-- rodar: shell -->
```bash
make reiniciar n=restauracao
docker logs dbe_restauracao 2>&1 | grep -E "restored log file|recovery stopping|selected new timeline|archive recovery complete"
```

```
LOG:  restored log file "00000001000000000000000E" from archive
LOG:  restored log file "00000001000000000000000F" from archive
LOG:  recovery stopping at restore point "antes_do_deploy", time 2026-10-19 13:17:00.314839-03
LOG:  selected new timeline ID: 2
LOG:  archive recovery complete
```

Leia o log de baixo para cima e você tem a história inteira: o servidor
buscou os segmentos no arquivo, reaplicou até o ponto `antes_do_deploy`,
parou ali e abriu uma **nova timeline**.

---

## 4.8 Conferindo e entendendo a timeline

🐘 **No psql do `restauracao`** (`make psql n=restauracao`):

<!-- rodar: restauracao -->
```sql
SELECT pg_is_in_recovery()                    AS em_recuperacao,
       (SELECT count(*) FROM pedidos)          AS pedidos,
       (SELECT sum(valor_unit) FROM produtos)  AS soma_dos_precos;
```

```
 em_recuperacao | pedidos | soma_dos_precos
----------------+---------+-----------------
 f              |  103985 |       504547.61
(1 row)
```

Os mesmos números que você anotou antes do deploy: os preços certos e os
pedidos daquele instante.

🖥️ **No seu terminal:**

<!-- rodar: shell -->
```bash
make status
```

```
NÓ           SITUAÇÃO               PAPEL        TL  LSN          LÊ DE      RÉPLICAS PG
primario     no ar                  primário     1   0/10000000   -          0        17
replica1     esperando dados
replica2     esperando dados
restauracao  no ar                  primário     2   0/F0AB128    -          0        17
logico       no ar                  primário     1   0/1BEFEF0    -          0        18
```

Veja a coluna **TL**: o `primario` está na timeline **1** e o `restauracao`
na **2**. Até `antes_do_deploy` os dois viveram a mesma história. Dali em
diante, o `primario` seguiu com o bug e as vendas a um centavo, e o
`restauracao` seguiu um caminho em que o bug nunca aconteceu. São duas
**linhas do tempo** que se separaram num ponto:

```
 timeline 1:  ──────●────────── UPDATE (bug) ──── vendas a 1 centavo ───►  primario
                    │
       antes_do_deploy
                    │
 timeline 2:        └──────────────────────────────────────────────────►  restauracao
```

É por isso que o nome de todo segmento de WAL começa pela timeline
(`00000001...`, `00000002...`): para que as duas histórias nunca se misturem
no arquivo. Você vai reencontrar as timelines no failover da etapa 7.

---

## 4.9 Consertando a produção

Exporte do `restauracao` os preços certos para o storage de backup:

🐘 **No psql do `restauracao`:**

<!-- rodar: restauracao -->
```sql
COPY (SELECT id, valor_unit FROM produtos ORDER BY id)
  TO '/backup/precos_corretos.csv' WITH (FORMAT csv, HEADER);
```

```
COPY 200
```

E aplique na produção, numa transação só:

🐘 **No psql do `primario`:**

<!-- rodar: primario -->
```sql
BEGIN;

CREATE TEMP TABLE precos_corretos (id int PRIMARY KEY, valor_unit numeric(10,2));
COPY precos_corretos FROM '/backup/precos_corretos.csv' WITH (FORMAT csv, HEADER);

UPDATE produtos p
   SET valor_unit = c.valor_unit
  FROM precos_corretos c
 WHERE c.id = p.id;

SELECT sum(valor_unit) AS soma_dos_precos FROM produtos;

COMMIT;
```

```
BEGIN
CREATE TABLE
COPY 200
UPDATE 200
 soma_dos_precos
-----------------
       504547.61
(1 row)

COMMIT
```

Preços de volta. E as vendas de depois do bug continuam lá:

<!-- rodar: primario -->
```sql
SELECT count(*) AS pedidos FROM pedidos;

SELECT count(*) AS vendas_a_um_centavo FROM itens_pedidos WHERE valor_total <= 0.03;
```

```
 pedidos
---------
  104985
(1 row)

 vendas_a_um_centavo
---------------------
                1000
(1 row)
```

A loja não parou um segundo e nenhuma venda se perdeu. A lista das vendas a
um centavo vai para a diretoria decidir.

---

## 4.10 Outros alvos de restauração

Aqui você usou um ponto com nome porque o time foi disciplinado. Na vida
real, quase sempre você só sabe **a hora**:

| Configuração | Para quando | Exemplo |
|---|---|---|
| `recovery_target_name` | houve um `pg_create_restore_point` | `'antes_do_deploy'` |
| `recovery_target_time` | você sabe a hora do problema | `'2026-10-19 14:03:00-03'` |
| `recovery_target_xid` | você achou a transação culpada (com `pg_waldump`) | `'48213'` |
| `recovery_target_lsn` | você sabe a posição exata no WAL | `'0/10066918'` |
| *(nenhum)* | voltar **tudo**, até o último WAL arquivado | o disco morreu |

E duas opções que mudam o comportamento:

* **`recovery_target_inclusive = off`**: para **antes** da transação alvo,
  em vez de logo depois dela.
* **`recovery_target_action = 'pause'`**: chega ao ponto e **fica parado**,
  só leitura, para você conferir. Se estiver certo, `SELECT pg_wal_replay_resume()`
  promove. Se não, você muda o alvo e tenta de novo, sem refazer a cópia.
  Quando você não tem certeza da hora, é o modo mais seguro.

Repetir esta etapa com `recovery_target_time` é um dos
[desafios](../../desafios/desafios.md).

---

## 4.11 O novo quadro

| Cenário | Antes | Agora |
|---|---|---|
| Alguém apaga uma tabela | perde a tabela | volta ao segundo anterior (num outro servidor) |
| O disco morre | perde tudo | restaura o backup e reaplica o WAL: perde **no máximo 60 s** (`archive_timeout`) |
| RTO | para sempre | o tempo de copiar o backup **e reaplicar o WAL** desde ele |

Repare no RTO: quanto mais antigo o backup base, mais WAL para reaplicar.
É por isso que, mesmo com arquivamento, se faz um backup base novo toda
semana (ou todo dia). Mas ainda é um RTO de **minutos a horas**, e alguém
precisa estar acordado para fazer tudo isso. Para cair e voltar em segundos,
você precisa de outro servidor **já pronto**, recebendo o WAL ao vivo. É a
próxima etapa.

---

## ✔️ Confira

🖥️ **No seu terminal:**

<!-- rodar: shell -->
```bash
make conferir e=4
```

```
Conferindo a etapa 4 - PITR

  ✅ arquivamento ligado e sem falhas (4 segmentos arquivados)
  ✅ backup base com arquivamento em /backup/base/pitr
  ✅ restauracao recuperado até um ponto anterior ao deploy (timeline 2)
  ✅ preços da produção iguais aos do restauracao (soma 504547.61)
  ✅ as vendas de depois do bug continuam na produção (1000 a mais que no restauracao)

✅ Etapa 4 conferida.
```

---

# ➡️ Continue em [5. Replicação assíncrona](../05_replicacao_assincrona/README.md)
