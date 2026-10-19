# 8️⃣ Replicação lógica

> ⬅️ Anterior: [7. Failover e switchover](../07_failover/README.md) · [README principal](../../README.md) · Etapa 8 de 10

> **A pergunta da diretoria:** "Dá para migrar para o PostgreSQL 18 sem parar
> a loja?"

A replicação física das etapas 5 a 7 copia **bytes**: o servidor inteiro,
bloco a bloco. Por isso ela é perfeita para alta disponibilidade, mas tem três
limites:

* a réplica precisa ser da **mesma versão** do PostgreSQL;
* vai **tudo**, todos os bancos e todas as tabelas, sem escolha;
* a réplica é **somente leitura**.

A **replicação lógica** copia **linhas**: "inseriu esta linha na tabela
`pedidos`", "alterou aquela em `produtos`". Ela escolhe tabelas, atravessa
versões, e o destino é um banco normal, que aceita escrita.

O nó `logico` é um **PostgreSQL 18** recém-instalado. Nesta etapa você o
alimenta com a replicação lógica a partir do `primario` (versão 17), quebra a
replicação de duas formas diferentes, conserta, e ensaia a virada de versão.

| | Física (etapas 5 a 7) | Lógica (esta etapa) |
|---|---|---|
| Copia | blocos do disco (o WAL cru) | linhas (o WAL traduzido) |
| Escopo | o servidor inteiro | as tabelas que você escolher |
| Versões | iguais | podem ser diferentes |
| Destino | somente leitura | aceita escrita (e isso é um perigo) |
| `CREATE`/`ALTER TABLE` | replicados | **não** replicados |
| Sequências | replicadas | **não** replicadas |
| Uso típico | alta disponibilidade | migração de versão, alimentar BI, juntar bancos |

---

## 8.1 O WAL precisa de mais detalhe

Na etapa 1 você viu `wal_level = replica`: o WAL tem o suficiente para
**refazer blocos**, mas não para dizer **qual linha** de **qual tabela**
mudou. A replicação lógica precisa do nível `logical`. É `postmaster`:
exige reiniciar.

🐘 **No psql do `primario`** (`make psql n=primario`):

<!-- rodar: primario -->
```sql
ALTER SYSTEM SET wal_level = 'logical';
```

🖥️ **No seu terminal:**

<!-- rodar: shell -->
```bash
make reiniciar n=primario
sleep 2
make status
```

A loja ficou fora por alguns segundos. As réplicas físicas perderam a conexão
e se reconectaram sozinhas.

🐘 **No psql do `primario`:**

<!-- rodar: primario -->
```sql
SHOW wal_level;
```

```
 wal_level
-----------
 logical
(1 row)
```

---

## 8.2 A publicação: o que sai

Do lado de quem envia, você cria uma **publicação**: a lista de tabelas a
replicar.

<!-- rodar: primario -->
```sql
CREATE PUBLICATION pub_loja
    FOR TABLE categorias, produtos, pessoas, pedidos, itens_pedidos;

GRANT SELECT ON ALL TABLES IN SCHEMA public TO replicador;

SELECT pubname, tablename FROM pg_publication_tables ORDER BY tablename;
```

```
CREATE PUBLICATION
GRANT
 pubname  |   tablename
----------+---------------
 pub_loja | categorias
 pub_loja | itens_pedidos
 pub_loja | pedidos
 pub_loja | pessoas
 pub_loja | produtos
(5 rows)
```

* A tabela **`auditoria_pedidos` ficou de fora**, de propósito: ela tem o
  telefone dos clientes, e o servidor novo não precisa disso. É a
  **LGPD** na prática: dado pessoal só vai para onde precisa ir. (Dá para
  filtrar até **colunas** e **linhas**: veja os [desafios](../../desafios/desafios.md).)
* O `GRANT SELECT` existe porque a primeira coisa que o destino faz é **ler**
  as tabelas inteiras (a cópia inicial). O `replicador` precisa enxergá-las.

---

## 8.3 O destino precisa das tabelas

A replicação lógica copia **linhas**, e linhas precisam de uma tabela para
cair. Ela **não cria** tabela nenhuma: o `CREATE TABLE` precisa existir no
destino antes. O jeito mais seguro é copiar a **estrutura** do primário com o
`pg_dump --schema-only` que você conheceu na etapa 2.

🖥️ **No seu terminal:**

```bash
make bash n=logico
```

📦 **No terminal do `logico`:**

<!-- rodar: bash-logico -->
```bash
psql -U sudoers -d liga_sudoers -Atc "SELECT version()"

pg_dump -h primario -U sudoers -d liga_sudoers --schema-only --no-publications --no-privileges \
  | psql -q -U sudoers -d liga_sudoers > /dev/null

psql -U sudoers -d liga_sudoers -c "\dt"
```

```
PostgreSQL 18.6 (Debian 18.6-1.pgdg13+2) on x86_64-pc-linux-gnu, compiled by gcc (Debian 14.2.0-19) 14.2.0, 64-bit
              List of tables
 Schema |       Name        | Type  |  Owner
--------+-------------------+-------+---------
 public | auditoria_pedidos | table | sudoers
 public | categorias        | table | sudoers
 public | itens_pedidos     | table | sudoers
 public | pedidos           | table | sudoers
 public | pessoas           | table | sudoers
 public | produtos          | table | sudoers
 public | teste_failover    | table | sudoers
 public | teste_replicacao  | table | sudoers
(8 rows)
```

Repare: é o `pg_dump` da versão **18** lendo um servidor **17**. A regra é
sempre usar o `pg_dump` da versão **mais nova** (a do destino). As tabelas
existem, vazias. O `--no-publications` evita copiar a publicação (ela é do
primário) e o `--no-privileges` evita os `GRANT`s para o `replicador`, que não
existe neste servidor (usuários não vão no `pg_dump`, lembra da etapa 2?).

---

## 8.4 A assinatura: o que entra

Do lado de quem recebe, você cria uma **assinatura**: "conecte ali e receba
aquela publicação".

🐘 **No psql do `logico`** (`make psql n=logico`):

<!-- rodar: logico -->
```sql
CREATE SUBSCRIPTION sub_loja
    CONNECTION 'host=primario dbname=liga_sudoers user=replicador'
    PUBLICATION pub_loja;
```

```
NOTICE:  created replication slot "sub_loja" on publisher
CREATE SUBSCRIPTION
```

A assinatura faz duas coisas:

1. **cópia inicial**: lê cada tabela inteira do primário (um `COPY`);
2. **fluxo contínuo**: a partir dali, recebe cada mudança pelo **slot
   lógico** que ela criou no primário.

Espere alguns segundos e acompanhe a cópia inicial:

<!-- rodar: logico -->
```sql
SELECT pg_sleep(5);

SELECT srrelid::regclass AS tabela, srsubstate AS estado
FROM pg_subscription_rel ORDER BY 1;
```

```
    tabela     | estado
---------------+--------
 categorias    | r
 itens_pedidos | r
 pedidos       | r
 pessoas       | r
 produtos      | r
(5 rows)
```

`r` é *ready*: cópia inicial feita, fluxo contínuo rodando. (Durante a cópia
aparecem `i`, `d` e `s`.) Compare os números:

<!-- rodar: logico -->
```sql
SELECT (SELECT count(*) FROM pedidos)            AS pedidos,
       (SELECT count(*) FROM itens_pedidos)      AS itens,
       (SELECT count(*) FROM auditoria_pedidos)  AS auditoria;
```

```
 pedidos | itens  | auditoria
---------+--------+-----------
  153235 | 301166 |         0
(1 row)
```

🐘 **No psql do `primario`:**

<!-- rodar: primario -->
```sql
SELECT (SELECT count(*) FROM pedidos)            AS pedidos,
       (SELECT count(*) FROM itens_pedidos)      AS itens,
       (SELECT count(*) FROM auditoria_pedidos)  AS auditoria;

SELECT slot_name, slot_type, plugin, active FROM pg_replication_slots;
```

```
 pedidos | itens  | auditoria
---------+--------+-----------
  153235 | 301166 |    100000
(1 row)

 slot_name | slot_type |  plugin  | active
-----------+-----------+----------+--------
 replica1  | physical  |          | t
 replica2  | physical  |          | t
 sub_loja  | logical   | pgoutput | t
(3 rows)
```

Pedidos e itens iguais. A auditoria, de propósito, só no primário. E no
primário, ao lado dos slots físicos das réplicas, agora existe um slot
**lógico**, que usa o *plugin* `pgoutput` para traduzir o WAL em linhas.

---

## 8.5 Ao vivo

🖥️ **No seu terminal:**

<!-- rodar: shell -->
```bash
make carga t=5
sleep 2
for n in primario logico; do
  docker exec dbe_$n psql -U sudoers -d liga_sudoers -Atc \
    "SELECT '$n: ' || count(*) || ' pedidos, PostgreSQL ' || current_setting('server_version') FROM pedidos"
done
```

```
...
primario: 153719 pedidos, PostgreSQL 17.11 (Debian 17.11-1.pgdg13+2)
logico: 153719 pedidos, PostgreSQL 18.6 (Debian 18.6-1.pgdg13+2)
```

Vendas feitas no 17 aparecem no 18, ao vivo.

---

## 8.6 Primeira quebra: escrevendo no destino

Diferente da réplica física, o `logico` **aceita escrita**. Alguém do time de
BI, achando que é inofensivo, cadastra uma categoria direto nele.

🐘 **No psql do `logico`:**

<!-- rodar: logico falha-esperada -->
```sql
INSERT INTO categorias (descricao) VALUES ('Criada no logico');
```

```
ERROR:  duplicate key value violates unique constraint "categorias_pkey"
DETAIL:  Key (id)=(1) already exists.
```

Erro com `id = 1`? É a primeira surpresa: **sequências não são replicadas**.
As linhas vieram com os seus `id`s, mas a sequência `categorias_id_seq` do
`logico` ainda está no começo. A pessoa insiste e "conserta" a sequência:

<!-- rodar: logico -->
```sql
SELECT setval('categorias_id_seq', (SELECT max(id) FROM categorias));
INSERT INTO categorias (descricao) VALUES ('Criada no logico') RETURNING id;
```

```
 setval
--------
     13
(1 row)

 id
----
 14
(1 row)

INSERT 0 1
```

Agora, no primário, alguém cadastra uma categoria de verdade:

🐘 **No psql do `primario`:**

<!-- rodar: primario -->
```sql
INSERT INTO categorias (descricao) VALUES ('Games') RETURNING id;
```

```
 id
----
 14
(1 row)

INSERT 0 1
```

O mesmo `id` 14. Quando essa linha chega ao `logico`, não cabe. Veja o log:

🖥️ **No seu terminal:**

<!-- rodar: shell -->
```bash
sleep 3
docker logs dbe_logico 2>&1 | grep -E "conflict|DETAIL" | tail -2
```

```
ERROR:  conflict detected on relation "public.categorias": conflict=insert_exists
DETAIL:  Key already exists in unique index "categorias_pkey", modified in transaction 1322.
```

E o pior: a replicação **parou inteira**, não só a tabela `categorias`. A
assinatura aplica as mudanças **na ordem** em que aconteceram; enquanto a
categoria 14 não entrar, nada que veio depois entra:

<!-- rodar: shell -->
```bash
make carga t=5
sleep 2
for n in primario logico; do
  docker exec dbe_$n psql -U sudoers -d liga_sudoers -Atc "SELECT '$n: ' || count(*) || ' pedidos' FROM pedidos"
done
```

```
...
primario: 154204 pedidos
logico: 153719 pedidos
```

O `logico` parou no tempo. O PostgreSQL 18 conta os conflitos por tipo:

🐘 **No psql do `logico`:**

<!-- rodar: logico -->
```sql
SELECT subname, apply_error_count, confl_insert_exists
FROM pg_stat_subscription_stats;
```

```
 subname  | apply_error_count | confl_insert_exists
----------+-------------------+---------------------
 sub_loja |                 4 |                   4
(1 row)
```

Para destravar, o lado errado é o `logico`: apague a linha que não deveria
existir.

<!-- rodar: logico -->
```sql
DELETE FROM categorias WHERE descricao = 'Criada no logico';
SELECT pg_sleep(6);
SELECT id, descricao FROM categorias WHERE id > 12 ORDER BY id;
SELECT count(*) AS pedidos FROM pedidos;
```

```
 id |           descricao
----+--------------------------------
 13 | Criada depois do backup físico
 14 | Games
(2 rows)

 pedidos
---------
  154204
(1 row)
```

A categoria 14 entrou, e com ela tudo o que estava represado.

> **Regra:** num destino de replicação lógica, ninguém escreve nas tabelas
> replicadas. Em produção, isso se garante com permissão (só o usuário da
> assinatura escreve nelas).

---

## 8.7 Segunda quebra: `ALTER TABLE`

O time de produto quer controlar estoque e cria uma coluna no primário:

🐘 **No psql do `primario`:**

<!-- rodar: primario -->
```sql
ALTER TABLE produtos ADD COLUMN estoque integer NOT NULL DEFAULT 100;
UPDATE produtos SET estoque = 50 WHERE id = 1;
```

O `ALTER TABLE` **não viaja** pela replicação lógica. O `UPDATE` viaja, e
chega com uma coluna que o `logico` não tem:

🖥️ **No seu terminal:**

<!-- rodar: shell -->
```bash
sleep 3
docker logs dbe_logico 2>&1 | grep "missing replicated column" | tail -1
```

```
ERROR:  logical replication target relation "public.produtos" is missing replicated column: "estoque"
```

Travou de novo. O conserto é aplicar o mesmo DDL no destino:

🐘 **No psql do `logico`:**

<!-- rodar: logico -->
```sql
ALTER TABLE produtos ADD COLUMN estoque integer NOT NULL DEFAULT 100;
SELECT pg_sleep(6);
SELECT id, estoque FROM produtos WHERE id IN (1, 2) ORDER BY id;
```

```
 id | estoque
----+---------
  1 |      50
  2 |     100
(2 rows)
```

> **Regra:** com replicação lógica, toda mudança de estrutura é aplicada
> **primeiro no destino** e **depois na origem**. Coluna nova no destino
> primeiro (ela fica vazia, esperando); depois na origem (os dados começam a
> chegar). Para **remover** uma coluna, a ordem se inverte.

---

## 8.8 O slot lógico também segura WAL

O que vale para o slot físico (etapa 5) vale aqui, e é ainda mais comum de
esquecer: alguém desliga o servidor de BI e não avisa. Simule desativando a
assinatura:

🐘 **No psql do `logico`:**

<!-- rodar: logico -->
```sql
ALTER SUBSCRIPTION sub_loja DISABLE;
```

🖥️ **No seu terminal:**

<!-- rodar: shell -->
```bash
make carga t=10
```

🐘 **No psql do `primario`:**

<!-- rodar: primario -->
```sql
SELECT slot_name, slot_type, active,
       pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) AS wal_retido
FROM pg_replication_slots;
```

```
 slot_name | slot_type | active | wal_retido
-----------+-----------+--------+------------
 replica1  | physical  | t      | 0 bytes
 replica2  | physical  | t      | 0 bytes
 sub_loja  | logical   | f      | 598 kB
(3 rows)
```

O slot `sub_loja` está inativo e retendo WAL (o seu número pode ser outro,
pelo mesmo motivo da etapa 5: se um segmento foi fechado nesse meio tempo,
ele salta uns 16 MB). Um slot lógico esquecido é a
causa número 1 de "o disco do banco encheu sozinho". Reative:

🐘 **No psql do `logico`:**

<!-- rodar: logico -->
```sql
ALTER SUBSCRIPTION sub_loja ENABLE;
SELECT pg_sleep(5);
SELECT count(*) AS pedidos FROM pedidos;
```

Ele alcança o primário, e o slot libera o WAL.

---

## 8.9 Ensaiando a migração para o PostgreSQL 18

O `logico` está em dia com o primário. A virada de versão, no dia D, seria:

1. **parar as escritas** na aplicação (a única janela de indisponibilidade:
   segundos);
2. esperar o `logico` aplicar tudo o que falta;
3. **sincronizar as sequências** (elas não são replicadas, lembra?);
4. desligar a assinatura e **apontar a aplicação** para o `logico`.

Vamos ensaiar. O passo 1 é não rodar mais o `make carga`. O passo 2 é
conferir que nada falta: a posição que o slot já confirmou tem que alcançar a
posição atual do WAL.

🐘 **No psql do `primario`:**

<!-- rodar: primario -->
```sql
SELECT pg_sleep(2);
SELECT slot_name,
       pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), confirmed_flush_lsn)) AS falta_aplicar
FROM pg_replication_slots WHERE slot_type = 'logical';
```

```
 slot_name | falta_aplicar
-----------+---------------
 sub_loja  | 0 bytes
(1 row)
```

(Se aparecer um número pequeno, rode de novo: o primário escreve um pouco de
WAL de manutenção mesmo sem vendas.)

O passo 3: gere no primário um `setval` para cada sequência, com o valor
atual, e aplique no `logico`.

📦 **No terminal do `logico`** (`make bash n=logico`):

<!-- rodar: bash-logico -->
```bash
psql -h primario -U sudoers -d liga_sudoers -Atc "
  SELECT format('SELECT setval(%L, %s);', schemaname || '.' || sequencename, last_value)
  FROM pg_sequences WHERE last_value IS NOT NULL" > /tmp/sequencias.sql
cat /tmp/sequencias.sql
psql -q -U sudoers -d liga_sudoers -f /tmp/sequencias.sql > /dev/null
```

```
SELECT setval('public.categorias_id_seq', 14);
SELECT setval('public.produtos_id_seq', 200);
SELECT setval('public.pedidos_id_seq', 155283);
SELECT setval('public.teste_replicacao_id_seq', 34);
SELECT setval('public.teste_failover_id_seq', 67);
```

O passo 4: desligue a assinatura. Ao apagá-la, ela apaga também o slot lá no
primário (sem deixar lixo).

🐘 **No psql do `logico`:**

<!-- rodar: logico -->
```sql
DROP SUBSCRIPTION sub_loja;
```

```
NOTICE:  dropped replication slot "sub_loja" on publisher
DROP SUBSCRIPTION
```

Agora a "aplicação" vende no PostgreSQL 18:

🖥️ **No seu terminal:**

<!-- rodar: shell -->
```bash
make carga t=5 n=logico
```

```
Simulando vendas em logico por 5s, 100 vendas/s...
number of transactions actually processed: 466
latency average = 0.938 ms
tps = 93.141090 (without initial connection time)
```

Nenhum erro de chave duplicada: as sequências estavam certas. Num dia D de
verdade, a migração inteira custaria à loja **os segundos entre o passo 1 e
o passo 4**, contra as horas de um `pg_dump` + `pg_restore` de um banco grande.

### Desmontando o ensaio

A diretoria aprovou a migração para o próximo trimestre. Até lá, o `primario`
segue sendo a produção. Remova a publicação, para não deixar nada para trás:

🐘 **No psql do `primario`:**

<!-- rodar: primario -->
```sql
DROP PUBLICATION pub_loja;
SELECT slot_name, slot_type FROM pg_replication_slots;
```

```
DROP PUBLICATION
 slot_name | slot_type
-----------+-----------
 replica1  | physical
 replica2  | physical
(2 rows)
```

Só os slots das réplicas físicas. Nenhum slot lógico órfão.

---

## ✔️ Confira

🖥️ **No seu terminal:**

<!-- rodar: shell -->
```bash
make conferir e=8
```

```
Conferindo a etapa 8 - Replicação lógica

  ✅ primario com wal_level = logical
  ✅ logico é PostgreSQL 18 e recebeu os pedidos do primario (155700)
  ✅ produtos.estoque existe no logico (o DDL foi aplicado nos dois lados)
  ✅ sequências do logico sincronizadas (pedidos_id_seq à frente do maior id)
  ✅ ensaio desmontado: sem assinatura no logico, sem publicação e sem slot lógico no primario

✅ Etapa 8 conferida.
```

---

# ➡️ Continue em [9. Particionamento](../09_particionamento/README.md)
