# 9️⃣ Particionamento

> ⬅️ Anterior: [8. Replicação lógica](../08_replicacao_logica/README.md) · [README principal](../../README.md) · Etapa 9 de 10

> **A pergunta da diretoria:** "A tabela de pedidos não para de crescer. E
> agora?"

Toda venda vira uma linha em `pedidos`, e nenhuma linha sai. Hoje são 18
meses; daqui a cinco anos serão 100. Uma tabela que só cresce traz três
problemas, cada vez maiores:

1. **consultas por período leem tudo**: o faturamento do mês passado varre
   os cinco anos;
2. **apagar dados antigos é caro**: um `DELETE` de milhões de linhas gera
   WAL de milhões de linhas (que vai para o arquivo e para cada réplica) e
   deixa a tabela cheia de espaço morto;
3. **manutenção pesa**: `VACUUM`, criação de índice e backup de uma tabela
   gigante, de uma vez só.

**Particionar** é dividir uma tabela grande em várias menores (as
**partições**), de forma transparente: a aplicação continua lendo e
gravando em `pedidos`, e o PostgreSQL manda cada linha para a partição
certa. Nesta etapa você particiona `pedidos` por **mês**, com a loja aberta.

---

## 9.1 O diagnóstico

Quanto a loja vendeu no mês passado?

🐘 **No psql do `primario`** (`make psql n=primario`):

<!-- rodar: primario -->
```sql
EXPLAIN (ANALYZE, COSTS OFF)
SELECT count(*), sum(valor_total)
FROM pedidos
WHERE dt_venda >= date_trunc('month', now()) - interval '1 month'
  AND dt_venda <  date_trunc('month', now());
```

```
                                  QUERY PLAN
-------------------------------------------------------------------------------------
 Finalize Aggregate (actual time=16.049..17.167 rows=1 loops=1)
   ->  Gather (actual time=16.014..17.162 rows=2 loops=1)
         Workers Planned: 1
         Workers Launched: 1
         ->  Partial Aggregate (actual time=14.740..14.740 rows=1 loops=2)
               ->  Parallel Seq Scan on pedidos (actual time=10.685..14.551 rows=2780 loops=2)
                     Filter: ((dt_venda < date_trunc('month'::text, now())) AND ...)
                     Rows Removed by Filter: 74837
 Planning Time: 0.233 ms
 Execution Time: 17.196 ms
```

Leia de baixo para cima: **Seq Scan** (leitura da tabela inteira), dividida
entre 2 processos (`loops=2`), com **`Rows Removed by Filter: 74837`** em
cada um. Para achar os ~5.500 pedidos do mês passado, o banco leu a tabela
inteira e jogou fora mais de 95% das linhas. Com cinco anos de dados,
jogaria fora 99%.

---

## 9.2 A ideia

```
                           pedidos   (a tabela que a aplicação enxerga)
                              │
      ┌──────────────┬────────┴───────┬───────────────┬──────────────┐
      ▼              ▼                ▼               ▼              ▼
 pedidos_2025_04  pedidos_2025_05  ...  pedidos_2026_10  ...  pedidos_default
 (abr/2025)       (mai/2025)            (o mês atual)         (o que não couber)
```

* `pedidos` vira uma tabela **particionada**: ela não guarda nada, só
  distribui.
* Cada partição é uma tabela de verdade, com as linhas de **um mês**
  (`PARTITION BY RANGE (dt_venda)`).
* Uma consulta com filtro em `dt_venda` lê **só** as partições daquele
  período (*partition pruning*).
* Apagar um mês antigo vira **apagar uma tabela**: instantâneo, sem WAL de
  linha por linha.

---

## 9.3 O preço: as chaves

Particionar não é de graça, e o preço aparece nas chaves. Duas regras do
PostgreSQL:

**1. A chave primária precisa conter a coluna de particionamento.** Cada
partição tem o seu próprio índice. Garantir que um `id` é único **entre todas
as partições** exigiria consultar todas a cada `INSERT`. Por isso a chave
primária passa a ser `(id, dt_venda)`.

**2. Por consequência, ninguém mais pode ter chave estrangeira para
`pedidos(id)`.** Uma chave estrangeira precisa apontar para algo único, e
`id`, sozinho, não é mais garantidamente único. Hoje `itens_pedidos` e
`auditoria_pedidos` têm chave estrangeira para `pedidos(id)`. Elas vão
precisar ser removidas.

É uma decisão de arquitetura, não um detalhe: você troca uma garantia do
banco (a integridade referencial) por desempenho e facilidade de
manutenção. A alternativa é levar `dt_venda` também para as tabelas filhas e
usar uma chave estrangeira composta. É um dos [desafios](../../desafios/desafios.md).

---

## 9.4 Criando a tabela particionada

A estrutura é a mesma de `pedidos`, com a chave primária nova e a cláusula
`PARTITION BY`. O `id` continua usando a **mesma sequência** da tabela antiga,
para que a numeração siga de onde parou.

🐘 **No psql do `primario`:**

<!-- rodar: primario -->
```sql
CREATE TABLE pedidos_part (
    id           integer       NOT NULL DEFAULT nextval('pedidos_id_seq'),
    id_pessoa    bigint        NOT NULL REFERENCES pessoas (id),
    dt_venda     timestamp     NOT NULL,
    valor_total  numeric(10,2) NOT NULL,
    created_at   timestamp DEFAULT now(),
    updated_at   timestamp DEFAULT now(),
    PRIMARY KEY (id, dt_venda)
) PARTITION BY RANGE (dt_venda);
```

Agora as partições: uma por mês, do mês do pedido mais antigo até **três
meses no futuro**. Escrever 22 `CREATE TABLE` à mão seria chato e propenso a
erro, então um bloco `DO` (um pequeno programa em PL/pgSQL) gera todos:

<!-- rodar: primario -->
```sql
DO $$
DECLARE
    mes date;
BEGIN
    FOR mes IN
        SELECT generate_series(date_trunc('month', (SELECT min(dt_venda) FROM pedidos)),
                               date_trunc('month', now()) + interval '3 months',
                               interval '1 month')::date
    LOOP
        EXECUTE format('CREATE TABLE pedidos_%s PARTITION OF pedidos_part
                        FOR VALUES FROM (%L) TO (%L)',
                       to_char(mes, 'YYYY_MM'), mes, mes + interval '1 month');
    END LOOP;
END $$;

CREATE TABLE pedidos_default PARTITION OF pedidos_part DEFAULT;
```

* `FOR VALUES FROM ('2026-10-01') TO ('2026-11-01')`: o início **entra**, o
  fim **não**. Um pedido às `2026-11-01 00:00:00` vai para a partição de
  novembro. Sem buracos, sem sobreposição.
* A partição **`DEFAULT`** recebe o que não couber em nenhuma outra (uma data
  muito no futuro, por exemplo). Ela evita que um `INSERT` falhe, mas não
  deve acumular nada: se acumular, alguém esqueceu de criar partições.

<!-- rodar: primario -->
```sql
\d+ pedidos_part
```

```
                                     Partitioned table "public.pedidos_part"
   Column    |            Type             | Collation | Nullable |               Default               | ...
-------------+-----------------------------+-----------+----------+-------------------------------------+----
 id          | integer                     |           | not null | nextval('pedidos_id_seq'::regclass) | ...
 id_pessoa   | bigint                      |           | not null |                                     | ...
 dt_venda    | timestamp without time zone |           | not null |                                     | ...
 valor_total | numeric(10,2)               |           | not null |                                     | ...
 created_at  | timestamp without time zone |           |          | now()                               | ...
 updated_at  | timestamp without time zone |           |          | now()                               | ...
Partition key: RANGE (dt_venda)
Indexes:
    "pedidos_part_pkey" PRIMARY KEY, btree (id, dt_venda)
Foreign-key constraints:
    "pedidos_part_id_pessoa_fkey" FOREIGN KEY (id_pessoa) REFERENCES pessoas(id)
Partitions: pedidos_2025_04 FOR VALUES FROM ('2025-04-01 00:00:00') TO ('2025-05-01 00:00:00'),
            pedidos_2025_05 FOR VALUES FROM ('2025-05-01 00:00:00') TO ('2025-06-01 00:00:00'),
            ...
            pedidos_2026_10 FOR VALUES FROM ('2026-10-01 00:00:00') TO ('2026-11-01 00:00:00'),
            pedidos_2026_11 FOR VALUES FROM ('2026-11-01 00:00:00') TO ('2026-12-01 00:00:00'),
            pedidos_2026_12 FOR VALUES FROM ('2026-12-01 00:00:00') TO ('2027-01-01 00:00:00'),
            pedidos_2027_01 FOR VALUES FROM ('2027-01-01 00:00:00') TO ('2027-02-01 00:00:00'),
            pedidos_default DEFAULT
```

Os meses que aparecem são os da **sua** turma: as partições vão do mês do
primeiro pedido até três meses depois de hoje.

---

## 9.5 A troca, com a loja aberta

O plano: copiar os pedidos para a tabela nova e trocar os nomes, numa
**transação só**. Para nenhuma venda escapar durante a cópia, a tabela antiga
é travada para **escrita** (as leituras continuam). As vendas que chegarem
nesse meio-tempo **esperam** alguns instantes e entram já na tabela nova.

Para ver isso acontecer, ligue o simulador de vendas por 30 segundos num
terminal e, **enquanto ele roda**, cole a transação no psql.

🖥️ **No seu terminal:**

```bash
make carga t=30
```

🐘 **No psql do `primario`:**

<!-- teste: (make carga t=8 > /tmp/dbe_carga_particionamento.log 2>&1 &) ; sleep 2 -->

<!-- rodar: primario -->
```sql
\timing on
BEGIN;

LOCK TABLE pedidos IN EXCLUSIVE MODE;

INSERT INTO pedidos_part SELECT * FROM pedidos;

ALTER TABLE itens_pedidos     DROP CONSTRAINT fk_itens_pedido;
ALTER TABLE auditoria_pedidos DROP CONSTRAINT fk_auditoria_pedido;

ALTER TABLE pedidos      RENAME TO pedidos_legado;
ALTER TABLE pedidos_part RENAME TO pedidos;

ALTER SEQUENCE pedidos_id_seq OWNED BY pedidos.id;

CREATE TRIGGER set_updated_at_pedidos
    BEFORE UPDATE ON pedidos
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

COMMIT;
\timing off
```

```
Timing is on.
BEGIN
LOCK TABLE
INSERT 0 155430
Time: 548.658 ms
...
COMMIT
Time: 0.616 ms
```

Linha a linha:

| Comando | Por quê |
|---|---|
| `LOCK TABLE ... IN EXCLUSIVE MODE` | trava as escritas em `pedidos` até o `COMMIT`; as leituras seguem |
| `INSERT INTO pedidos_part SELECT *` | a cópia: cada linha cai sozinha na partição do seu mês |
| `DROP CONSTRAINT fk_...` | a regra 2 da seção 9.3 |
| os dois `RENAME` | a troca: a aplicação continua usando o nome `pedidos`, que agora é a particionada |
| `OWNED BY` | a sequência passa a "pertencer" à tabela nova |
| `CREATE TRIGGER` | o trigger de `updated_at` ficou na tabela antiga; a nova precisa do dela |

A loja ficou meio segundo sem conseguir **gravar** pedidos (o tempo do
`INSERT`). No terminal do `make carga`, a latência média, que era de 1 ms,
sobe por um instante, e **nenhuma venda falha** (`0 failed`):

```
progress: 5.0 s, 98.4 tps, lat 37.238 ms stddev 112.749, 0 failed, lag 32.136 ms
```

Com 100 milhões de linhas, esse meio segundo seriam
minutos, e aí se usa uma estratégia online (cópia em lotes, *triggers* de
sincronização, ou a replicação lógica da etapa 8).

<!-- teste: sleep 8; cat /tmp/dbe_carga_particionamento.log; ! grep -q ERROR /tmp/dbe_carga_particionamento.log -->

Confira que nada se perdeu e que as vendas continuam caindo no lugar certo:

<!-- rodar: primario -->
```sql
SELECT (SELECT count(*) FROM pedidos_legado)                                        AS legado,
       (SELECT count(*) FROM pedidos WHERE id <= (SELECT max(id) FROM pedidos_legado)) AS copiados,
       (SELECT count(*) FROM pedidos WHERE id >  (SELECT max(id) FROM pedidos_legado)) AS vendas_depois_da_troca;

SELECT tableoid::regclass AS particao, count(*)
FROM pedidos GROUP BY 1 ORDER BY 1 DESC LIMIT 4;
```

```
 legado | copiados | vendas_depois_da_troca
--------+----------+------------------------
 155430 |   155430 |                    600
(1 row)

    particao     | count
-----------------+-------
 pedidos_2026_10 | 59365
 pedidos_2026_09 |  5561
 pedidos_2026_08 |  5761
 pedidos_2026_07 |  5749
(4 rows)
```

Todos os pedidos copiados, as vendas novas entrando na tabela particionada,
na partição do mês corrente. (`tableoid` é uma coluna escondida que diz de
qual tabela física veio cada linha. O mês corrente tem muito mais pedidos
que os outros por causa de todo o `make carga` que você rodou na trilha:
é a sua "Black Friday".)

---

## 9.6 O mesmo relatório, agora

<!-- rodar: primario -->
```sql
ANALYZE pedidos;

EXPLAIN (ANALYZE, COSTS OFF)
SELECT count(*), sum(valor_total)
FROM pedidos
WHERE dt_venda >= date_trunc('month', now()) - interval '1 month'
  AND dt_venda <  date_trunc('month', now());
```

```
ANALYZE
                                  QUERY PLAN
-------------------------------------------------------------------------------------
 Aggregate (actual time=1.778..1.779 rows=1 loops=1)
   ->  Append (actual time=0.005..1.440 rows=5561 loops=1)
         Subplans Removed: 22
         ->  Seq Scan on pedidos_2026_09 pedidos_1 (actual time=0.004..1.286 rows=5561 loops=1)
               Filter: ((dt_venda < date_trunc('month'::text, now())) AND ...)
 Planning Time: 0.927 ms
 Execution Time: 1.796 ms
```

**`Subplans Removed: 22`**: das 23 partições, 22 foram descartadas e só a do
mês passado foi lida. Sem `Rows Removed by Filter`: cada linha lida era uma
linha útil. De 17 ms para 2 ms, e a diferença cresce junto com a tabela.

> Como o filtro usa `now()`, que só tem valor na hora de executar, o descarte
> aconteceu na **execução** (*runtime pruning*). Com uma data fixa
> (`'2026-09-01'`), o próprio planejador já descarta as partições e o plano
> mostra direto `Seq Scan on pedidos_2026_09`.

### Mas atenção: e quando o filtro não é a data?

<!-- rodar: primario -->
```sql
CREATE INDEX ON pedidos (id_pessoa);

EXPLAIN (COSTS OFF) SELECT * FROM pedidos WHERE id_pessoa = 42;
```

```
CREATE INDEX
                                    QUERY PLAN
-----------------------------------------------------------------------------------
 Append
   ->  Index Scan using pedidos_2025_04_id_pessoa_idx on pedidos_2025_04 pedidos_1
         Index Cond: (id_pessoa = 42)
   ->  Bitmap Heap Scan on pedidos_2025_05 pedidos_2
         Recheck Cond: (id_pessoa = 42)
         ->  Bitmap Index Scan on pedidos_2025_05_id_pessoa_idx
               Index Cond: (id_pessoa = 42)
...
   ->  Seq Scan on pedidos_2027_01 pedidos_22
         Filter: (id_pessoa = 42)
   ->  Seq Scan on pedidos_default pedidos_23
         Filter: (id_pessoa = 42)
(83 rows)
```

Duas lições num comando:

* um `CREATE INDEX` na tabela particionada cria o índice **em cada
  partição** (repare no nome `pedidos_2025_04_id_pessoa_idx`), inclusive nas
  que forem criadas no futuro;
* uma consulta que **não filtra pela data** visita **todas** as partições:
  23 buscas em vez de uma (as partições vazias, do futuro, nem usam o
  índice: um `Seq Scan` em tabela vazia é instantâneo). A chave de particionamento se escolhe pelo
  **padrão de acesso dominante**. Para a Liga Sudoers, quase toda consulta é
  "por período". Se fosse "por cliente", a escolha seria outra.

---

## 9.7 Apagando o passado: `DELETE` × `DROP`

A política da empresa é manter 18 meses no banco e mandar o resto para o
arquivo. Compare as duas formas de se livrar do mês mais antigo.

**Do jeito antigo**, na tabela legada (que ainda existe), com `DELETE`. Meça
o WAL gerado.

Antes de medir, um `CHECKPOINT`. O motivo: na primeira vez que uma página é
alterada depois de um checkpoint, o PostgreSQL grava no WAL a **página
inteira** (8 kB), e não só a mudança. É o que protege a página de ficar pela
metade se a energia cair no meio da gravação (são as *full-page writes*). O
servidor faz checkpoint sozinho a cada 5 minutos, então, sem o `CHECKPOINT`
manual, o seu resultado dependeria de quanto tempo passou desde o último. Com
ele, as duas medições começam nas mesmas condições.

🐘 **No psql do `primario`:**

<!-- rodar: primario -->
```sql
CHECKPOINT;
SELECT pg_current_wal_lsn() AS antes \gset

DELETE FROM pedidos_legado
WHERE dt_venda < (SELECT date_trunc('month', min(dt_venda)) + interval '2 months'
                  FROM pedidos_legado);

SELECT pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), :'antes')) AS wal_gerado_pelo_delete;
```

```
CHECKPOINT
DELETE 6273
 wal_gerado_pelo_delete
------------------------
 906 kB
(1 row)
```

Cada linha apagada virou um registro no WAL, que foi para o arquivo e para as
duas réplicas. E a tabela **não diminuiu**: as linhas viraram espaço morto,
esperando o `VACUUM`. Multiplique por milhões de linhas.

**Do jeito novo**: desanexar a partição mais antiga (ela vira uma tabela
comum), guardar um dump dela no storage de backup e apagá-la.

Primeiro, uma tentativa que **não** vai funcionar, e que ensina algo:

<!-- rodar: primario falha-esperada -->
```sql
SELECT min(c.relname) AS mais_antiga
FROM pg_inherits i JOIN pg_class c ON c.oid = i.inhrelid
WHERE i.inhparent = 'pedidos'::regclass AND c.relname <> 'pedidos_default' \gset

ALTER TABLE pedidos DETACH PARTITION :"mais_antiga" CONCURRENTLY;
```

```
ERROR:  cannot detach partitions concurrently when a default partition exists
```

O `DETACH ... CONCURRENTLY` desanexa sem travar a tabela, mas não é
permitido quando existe uma partição `DEFAULT`. Sem o `CONCURRENTLY`, o
`DETACH` trava `pedidos` por um instante (milissegundos), o que é aceitável.

📦 **No terminal do `primario`** (`make bash n=primario`):

<!-- rodar: bash-primario -->
```bash
psql_() { psql -U sudoers -d liga_sudoers -Atc "$1"; }
lsn()   { psql_ "SELECT pg_current_wal_lsn()"; }

MAIS_ANTIGA=$(psql_ "SELECT c.relname FROM pg_inherits i JOIN pg_class c ON c.oid = i.inhrelid
                     WHERE i.inhparent = 'pedidos'::regclass AND c.relname <> 'pedidos_default'
                     ORDER BY c.relname LIMIT 1")
echo "partição mais antiga: $MAIS_ANTIGA"

psql_ "CHECKPOINT"

A=$(lsn); psql_ "ALTER TABLE pedidos DETACH PARTITION $MAIS_ANTIGA"; B=$(lsn)

mkdir -p /backup/arquivo
pg_dump -U sudoers -d liga_sudoers -t $MAIS_ANTIGA -Fc -f /backup/arquivo/$MAIS_ANTIGA.dump

C=$(lsn); psql_ "DROP TABLE $MAIS_ANTIGA"; D=$(lsn)

psql_ "SELECT 'WAL gerado pelo DETACH + DROP: ' ||
        pg_size_pretty(pg_wal_lsn_diff('$B', '$A') + pg_wal_lsn_diff('$D', '$C'))"
ls -lh /backup/arquivo
```

```
partição mais antiga: pedidos_2025_04
CHECKPOINT
ALTER TABLE
DROP TABLE
WAL gerado pelo DETACH + DROP: 281 kB
total 16K
-rw-r--r-- 1 postgres postgres 13K Oct 19 13:20 pedidos_2025_04.dump
```

(O WAL é medido em duas janelas curtas, uma em volta do `DETACH` e outra em
volta do `DROP`, para que o tempo do `pg_dump` não entre na conta.)

**Uns 300 kB de WAL**, contra uns 900 kB do `DELETE`. Com tão poucos dados a
diferença parece pequena, e a comparação nem é exata: o `DELETE` apagou os
**dois** meses mais antigos (uns 6 mil pedidos), e a partição removida tem
só o primeiro mês, que começa pela metade. A lição está em outro lugar: o
custo do `DROP` é praticamente **fixo** (são as páginas do catálogo do
PostgreSQL que mudam), enquanto o do `DELETE` **cresce com o número de
linhas**. Aqui um mês tem uns 5 mil pedidos. Com 5 milhões, o `DELETE`
geraria perto de 1 GB de WAL, que iria para o arquivo e para cada réplica; o
`DROP`, os mesmos 300 kB. O `DROP TABLE` não apaga linha por linha: ele
remove o arquivo. E o mês está guardado no arquivo morto: se a auditoria
pedir, é um `pg_restore` (etapa 2).

---

## 9.8 E as réplicas?

A replicação física copia blocos, então copiou tudo isso: a tabela nova, as
partições, os índices, os `RENAME`s, o `DROP`.

🐘 **No psql do `replica1`** (`make psql n=replica1`):

<!-- rodar: replica1 -->
```sql
SELECT c.relname, c.relkind, count(i.inhrelid) AS particoes
FROM pg_class c LEFT JOIN pg_inherits i ON i.inhparent = c.oid
WHERE c.relname = 'pedidos' GROUP BY 1, 2;
```

```
 relname | relkind | particoes
---------+---------+-----------
 pedidos | p       |        22
(1 row)
```

`relkind = p` é *partitioned table*. Compare com a etapa 8: na replicação
**lógica**, você teria de refazer cada um desses comandos no destino, à mão.

---

## 9.9 Arrumando a casa

A tabela legada cumpriu o papel (validar a cópia e servir de comparação).
Apague-a, e dê à chave primária o nome que ela sempre teve:

🐘 **No psql do `primario`:**

<!-- rodar: primario -->
```sql
DROP TABLE pedidos_legado;
ALTER TABLE pedidos RENAME CONSTRAINT pedidos_part_pkey TO pedidos_pkey;

\d pedidos
```

```
DROP TABLE
ALTER TABLE
                                   Partitioned table "public.pedidos"
   Column    |            Type             | Collation | Nullable |               Default
-------------+-----------------------------+-----------+----------+-------------------------------------
 id          | integer                     |           | not null | nextval('pedidos_id_seq'::regclass)
 id_pessoa   | bigint                      |           | not null |
 dt_venda    | timestamp without time zone |           | not null |
 valor_total | numeric(10,2)               |           | not null |
 created_at  | timestamp without time zone |           |          | now()
 updated_at  | timestamp without time zone |           |          | now()
Partition key: RANGE (dt_venda)
Indexes:
    "pedidos_pkey" PRIMARY KEY, btree (id, dt_venda)
    "pedidos_id_pessoa_idx" btree (id_pessoa)
Foreign-key constraints:
    "pedidos_part_id_pessoa_fkey" FOREIGN KEY (id_pessoa) REFERENCES pessoas(id)
Triggers:
    set_updated_at_pedidos BEFORE UPDATE ON pedidos FOR EACH ROW EXECUTE FUNCTION update_updated_at_column()
Number of partitions: 22 (Use \d+ to list them.)
```

### O que acontece daqui a quatro meses?

As partições vão até três meses no futuro. Depois disso, as vendas caem na
`pedidos_default`, e ela começa a crescer. Pior: quando alguém for criar a
partição daquele mês, o PostgreSQL **recusa**, porque já existem linhas dele
na `DEFAULT`. Criar partições **com antecedência** é uma tarefa recorrente:
em produção, quem faz é a extensão `pg_partman` (ou um agendador como o
`pg_cron`). Automatizar isso é um dos [desafios](../../desafios/desafios.md).

---

## 9.10 Os outros dois tipos

Por **faixa** (`RANGE`) é o mais comum, mas existem mais dois. Veja os dois
numa cópia descartável da auditoria e dos itens:

🐘 **No psql do `primario`:**

<!-- rodar: primario -->
```sql
-- LIST: cada partição recebe uma LISTA de valores
CREATE TABLE auditoria_por_canal (LIKE auditoria_pedidos) PARTITION BY LIST (dispositivo);
CREATE TABLE auditoria_mobile  PARTITION OF auditoria_por_canal
    FOR VALUES IN ('Android', 'iPhone', 'iPad', 'Web Mobile');
CREATE TABLE auditoria_desktop PARTITION OF auditoria_por_canal
    FOR VALUES IN ('Web Desktop');
INSERT INTO auditoria_por_canal SELECT * FROM auditoria_pedidos;

-- HASH: o PostgreSQL espalha as linhas por igual, pelo resto de uma conta
CREATE TABLE itens_hash (LIKE itens_pedidos) PARTITION BY HASH (id_pedido);
CREATE TABLE itens_hash_0 PARTITION OF itens_hash FOR VALUES WITH (MODULUS 4, REMAINDER 0);
CREATE TABLE itens_hash_1 PARTITION OF itens_hash FOR VALUES WITH (MODULUS 4, REMAINDER 1);
CREATE TABLE itens_hash_2 PARTITION OF itens_hash FOR VALUES WITH (MODULUS 4, REMAINDER 2);
CREATE TABLE itens_hash_3 PARTITION OF itens_hash FOR VALUES WITH (MODULUS 4, REMAINDER 3);
INSERT INTO itens_hash SELECT * FROM itens_pedidos;

SELECT tableoid::regclass AS particao, count(*) FROM auditoria_por_canal GROUP BY 1
UNION ALL
SELECT tableoid::regclass, count(*) FROM itens_hash GROUP BY 1
ORDER BY 1;
```

```
     particao      | count
-------------------+-------
 auditoria_mobile  | 79937
 auditoria_desktop | 20063
 itens_hash_0      | 76331
 itens_hash_1      | 75774
 itens_hash_2      | 75935
 itens_hash_3      | 75921
(6 rows)
```

| Tipo | Divide por | Bom para |
|---|---|---|
| `RANGE` | faixas (datas, números) | dado que envelhece: pedidos, logs, eventos |
| `LIST` | valores exatos | categorias fixas: país, canal, cliente grande × pequeno |
| `HASH` | resto de uma conta sobre a chave | espalhar escrita por igual, quando não há faixa natural |

E dá para combinar: cada partição pode, ela mesma, ser particionada
(subparticionamento), por exemplo por mês e, dentro do mês, por canal.

Foram só para ver. Apague as duas:

<!-- rodar: primario -->
```sql
DROP TABLE auditoria_por_canal;
DROP TABLE itens_hash;
```

---

## ✔️ Confira

🖥️ **No seu terminal:**

<!-- rodar: shell -->
```bash
make conferir e=9
```

```
Conferindo a etapa 9 - Particionamento

  ✅ pedidos é uma tabela particionada por faixa de dt_venda (22 partições)
  ✅ chave primária pedidos_pkey (id, dt_venda) e índice em id_pessoa
  ✅ partição DEFAULT vazia
  ✅ a partição mais antiga foi arquivada em /backup/arquivo e removida
  ✅ pedidos_legado removida
  ✅ replica1 e replica2 também enxergam pedidos particionada

✅ Etapa 9 conferida.
```

Parabéns: a Liga Sudoers tem backup lógico e físico, PITR, duas réplicas, um
plano de failover testado, um ensaio de migração de versão e uma tabela de
pedidos preparada para crescer. Volte ao diagnóstico da etapa 1 e compare.

---

# ➡️ Continue nos [Desafios](../../desafios/desafios.md)
