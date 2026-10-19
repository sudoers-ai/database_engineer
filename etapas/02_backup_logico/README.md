# 2️⃣ Backup lógico

> ⬅️ Anterior: [1. Conhecer o primário](../01_primario/README.md) · [README principal](../../README.md) · Etapa 2 de 10

> **A pergunta da diretoria:** "Alguém apagou uma tabela. A gente consegue
> voltar?"

Hoje a resposta é **não**. Nesta etapa você cria o primeiro backup da Liga
Sudoers, assiste a um estagiário apagar uma tabela em produção e traz a
tabela de volta. No caminho, descobre o limite desse tipo de backup.

**Backup lógico** é o backup que guarda o banco como **comandos**: "crie esta
tabela, insira estas linhas, crie este índice". A ferramenta é o `pg_dump`.

---

## 2.1 Três formatos de dump

Entre no servidor.

🖥️ **No seu terminal:**

```bash
make bash n=primario
```

📦 **No terminal do `primario`:**

<!-- rodar: bash-primario -->
```bash
mkdir -p /backup/dumps
cd /backup/dumps

# formato texto (plain): um arquivo .sql comum, legível
time pg_dump -U sudoers -d liga_sudoers -f liga_sudoers.sql

# formato custom (-Fc): um arquivo compactado, com índice interno
time pg_dump -U sudoers -d liga_sudoers -Fc -f liga_sudoers.dump

# formato diretório (-Fd): uma pasta, um arquivo por tabela; aceita paralelismo (-j)
time pg_dump -U sudoers -d liga_sudoers -Fd -j 4 -f liga_sudoers_dir

du -sh *
```

```
real	0m0.178s
...
real	0m0.780s
...
real	0m0.360s
...
6.1M	liga_sudoers_dir
6.1M	liga_sudoers.dump
30M	liga_sudoers.sql
```

| Formato | Tamanho | Para que serve |
|---|---|---|
| texto (`.sql`) | o maior | ler, versionar, editar à mão; restaura com `psql` |
| custom (`-Fc`) | ~5× menor | o padrão do dia a dia; restaura **só uma parte** com `pg_restore` |
| diretório (`-Fd`) | ~5× menor | bancos grandes: faz e restaura **em paralelo** (`-j`) |

> A pasta `/backup` é o "storage de backup" da empresa: ela existe em todos os
> nós do cluster. Em produção, ela seria um disco em **outra máquina** (ou um
> bucket na nuvem). Backup no mesmo disco do banco não é backup.

---

## 2.2 O que tem dentro

O formato texto é só SQL:

<!-- rodar: bash-primario -->
```bash
grep -n -m1 -A8 "CREATE TABLE public.pedidos" /backup/dumps/liga_sudoers.sql
grep -c "" /backup/dumps/liga_sudoers.sql
```

```
114:CREATE TABLE public.pedidos (
115-    id integer NOT NULL,
116-    id_pessoa bigint NOT NULL,
117-    dt_venda timestamp without time zone NOT NULL,
118-    valor_total numeric(10,2) NOT NULL,
119-    created_at timestamp without time zone DEFAULT now(),
120-    updated_at timestamp without time zone DEFAULT now()
121-);
122-
454132
```

São 454 mil linhas de SQL. Os dados vêm depois da estrutura, em blocos
`COPY ... FROM stdin`, e os índices e chaves
estrangeiras só **no final**: é mais rápido carregar a tabela sem índice e
criar o índice uma vez só.

O formato custom tem um **sumário** (*TOC*, *table of contents*), que o
`pg_restore -l` mostra:

<!-- rodar: bash-primario -->
```bash
pg_restore -l /backup/dumps/liga_sudoers.dump | grep -v "^;"
```

```
230; 1255 16459 FUNCTION public update_updated_at_column() sudoers
227; 1259 16447 TABLE public auditoria_pedidos sudoers
221; 1259 16394 TABLE public categorias sudoers
...
3499; 0 16447 TABLE DATA public auditoria_pedidos sudoers
3493; 0 16394 TABLE DATA public categorias sudoers
3498; 0 16430 TABLE DATA public itens_pedidos sudoers
...
3330; 2606 16436 CONSTRAINT public itens_pedidos pkey_itens_pedidos sudoers
...
3344; 2620 16464 TRIGGER public itens_pedidos set_updated_at_itens_pedidos sudoers
...
3337; 2606 16437 FK CONSTRAINT public itens_pedidos fk_itens_pedido sudoers
3338; 2606 16442 FK CONSTRAINT public itens_pedidos fk_itens_produto sudoers
...
```

Cada linha é um objeto que pode ser restaurado **separadamente**. É isso que
vai salvar o dia daqui a pouco.

---

## 2.3 O que o `pg_dump` não leva

O `pg_dump` faz backup de **um banco**. Usuários e senhas não pertencem a um
banco, e sim ao servidor inteiro. Eles ficam de fora:

<!-- rodar: bash-primario -->
```bash
grep -c "CREATE ROLE" /backup/dumps/liga_sudoers.sql || true
pg_dumpall -U sudoers --globals-only -f /backup/dumps/globais.sql
grep "ROLE" /backup/dumps/globais.sql
```

```
0
CREATE ROLE sudoers;
ALTER ROLE sudoers WITH SUPERUSER INHERIT CREATEROLE CREATEDB LOGIN REPLICATION BYPASSRLS PASSWORD 'SCRAM-SHA-256$4096:d49AEeO9...';
```

**Regra prática:** todo backup lógico é `pg_dump` de cada banco **mais**
`pg_dumpall --globals-only`. Sem os usuários, a restauração num servidor novo
falha em todo `GRANT` e todo `OWNER TO`.

---

## 2.4 A loja não para

Um detalhe que costuma passar despercebido: o `pg_dump` **não trava a loja**.
Ele abre uma transação e lê o banco como ele estava naquele instante (é o
MVCC: cada transação enxerga uma "foto" consistente). Quem compra durante o
dump compra normalmente; a venda só não entra no dump.

Depois do backup, a vida segue. Simule 10 segundos de vendas.

🖥️ **No seu terminal** (o primeiro, fora do container):

<!-- rodar: shell -->
```bash
make carga t=10
```

```
Simulando vendas em primario por 10s, 100 vendas/s...
progress: 5.0 s, 101.6 tps, lat 0.870 ms stddev 0.214, 0 failed, lag 0.097 ms
number of transactions actually processed: 1036
latency average = 0.858 ms
tps = 103.745451 (without initial connection time)
```

Cerca de **mil vendas** que não estão no dump. Guarde esse número.

---

## 2.5 O incidente

Um estagiário, achando que estava no banco de testes, roda:

🐘 **No psql do `primario`** (`make psql n=primario`):

<!-- rodar: primario -->
```sql
DROP TABLE itens_pedidos;
```

```
DROP TABLE
```

Sem confirmação, sem lixeira. Os itens de 18 meses de vendas sumiram:

<!-- rodar: primario falha-esperada -->
```sql
SELECT count(*) FROM itens_pedidos;
```

```
ERROR:  relation "itens_pedidos" does not exist
LINE 1: SELECT count(*) FROM itens_pedidos;
                             ^
```

> Respire. É para isso que você fez o backup. E repare: o banco **não**
> perguntou "tem certeza?". Em produção, a proteção é outra: o estagiário não
> deveria ter permissão de `DROP` (veja os [desafios](../../desafios/desafios.md)).

---

## 2.6 Trazendo **só** a tabela de volta

Restaurar o dump inteiro por cima do banco seria um desastre maior: você
voltaria **todas** as tabelas para o momento do backup e perderia as mil
vendas da tabela `pedidos`. O certo é restaurar **só** o que sumiu.

Primeiro, liste no sumário tudo que pertence à tabela:

📦 **No terminal do `primario`:**

<!-- rodar: bash-primario -->
```bash
pg_restore -l /backup/dumps/liga_sudoers.dump | grep itens_pedidos | tee /tmp/so_itens.txt
```

```
226; 1259 16430 TABLE public itens_pedidos sudoers
3498; 0 16430 TABLE DATA public itens_pedidos sudoers
3330; 2606 16436 CONSTRAINT public itens_pedidos pkey_itens_pedidos sudoers
3344; 2620 16464 TRIGGER public itens_pedidos set_updated_at_itens_pedidos sudoers
3337; 2606 16437 FK CONSTRAINT public itens_pedidos fk_itens_pedido sudoers
3338; 2606 16442 FK CONSTRAINT public itens_pedidos fk_itens_produto sudoers
```

São seis objetos: a tabela, os dados, a chave primária, o trigger e as duas
chaves estrangeiras. Agora restaure exatamente essa lista (`-L`):

<!-- rodar: bash-primario -->
```bash
pg_restore -U sudoers -d liga_sudoers -L /tmp/so_itens.txt --verbose /backup/dumps/liga_sudoers.dump
```

```
pg_restore: connecting to database for restore
pg_restore: creating TABLE "public.itens_pedidos"
pg_restore: processing data for table "public.itens_pedidos"
pg_restore: creating CONSTRAINT "public.itens_pedidos pkey_itens_pedidos"
pg_restore: creating TRIGGER "public.itens_pedidos set_updated_at_itens_pedidos"
pg_restore: creating FK CONSTRAINT "public.itens_pedidos fk_itens_pedido"
pg_restore: creating FK CONSTRAINT "public.itens_pedidos fk_itens_produto"
```

> **Por que não `pg_restore -t itens_pedidos`?** Porque o `-t` traz só a
> tabela e os dados: sem chave primária, sem trigger e sem chave estrangeira.
> A tabela "volta", mas aceita item duplicado e o `updated_at` para de
> funcionar. É um erro silencioso, do tipo que só aparece semanas depois.

---

## 2.7 Quanto se perdeu?

🐘 **No psql do `primario`:**

<!-- rodar: primario -->
```sql
\d itens_pedidos
```

```
                        Table "public.itens_pedidos"
   Column    |            Type             | Collation | Nullable | Default
-------------+-----------------------------+-----------+----------+---------
 id_pedido   | integer                     |           | not null |
 id_produto  | integer                     |           | not null |
 qtde        | integer                     |           | not null |
 valor_total | numeric(10,2)               |           | not null |
 created_at  | timestamp without time zone |           |          | now()
 updated_at  | timestamp without time zone |           |          | now()
Indexes:
    "pkey_itens_pedidos" PRIMARY KEY, btree (id_pedido, id_produto)
Foreign-key constraints:
    "fk_itens_pedido" FOREIGN KEY (id_pedido) REFERENCES pedidos(id)
    "fk_itens_produto" FOREIGN KEY (id_produto) REFERENCES produtos(id)
Triggers:
    set_updated_at_itens_pedidos BEFORE UPDATE ON itens_pedidos FOR EACH ROW EXECUTE FUNCTION update_updated_at_column()
```

A tabela voltou inteira, com chaves e trigger. Agora a pergunta incômoda:
quantos pedidos ficaram **sem item**?

<!-- rodar: primario -->
```sql
SELECT count(*) AS pedidos_sem_item
FROM pedidos p
WHERE NOT EXISTS (SELECT 1 FROM itens_pedidos i WHERE i.id_pedido = p.id);
```

```
 pedidos_sem_item
------------------
             1036
(1 row)
```

São as vendas que aconteceram **depois do dump** (o número da seção 2.4).
O pedido existe, o cliente pagou, mas o que ele comprou se perdeu. Esse é o
**RPO** do backup lógico: **tudo o que aconteceu desde o último dump**. Com
um dump por noite, o RPO é de até 24 horas.

---

## 2.8 Restaurando o banco inteiro (em paralelo)

Outro uso comum do dump: criar uma cópia do banco, para teste ou para
investigar um problema sem tocar na produção. O formato diretório restaura
em paralelo:

📦 **No terminal do `primario`:**

<!-- rodar: bash-primario -->
```bash
createdb -U sudoers liga_sudoers_copia
time pg_restore -U sudoers -d liga_sudoers_copia -j 4 /backup/dumps/liga_sudoers_dir
psql -U sudoers -d liga_sudoers_copia -c "SELECT count(*) AS pedidos FROM pedidos"
```

```
real	0m0.284s
...
 pedidos
---------
  101981
(1 row)
```

A cópia tem os pedidos do momento do dump (os 100 mil iniciais mais os da
carga da etapa 1). Feita a investigação, apague-a:

<!-- rodar: bash-primario -->
```bash
dropdb -U sudoers liga_sudoers_copia
```

---

## 2.9 O limite do backup lógico

O dump resolveu o incidente, mas olhe para ele com os olhos do CTO:

| | Backup lógico |
|---|---|
| **RPO** | o intervalo entre dumps (horas) |
| **RTO** | cresce com o banco: restaurar = **recriar** cada tabela e **cada índice**. Num banco de 1 TB, isso leva horas |
| **Ponto forte** | granularidade: restaura uma tabela, um schema; migra entre versões do PostgreSQL |
| **Não serve para** | voltar o servidor inteiro rápido, nem voltar a um minuto qualquer |

Para voltar o servidor **inteiro** e **rápido**, você precisa de outro tipo
de backup: a cópia dos arquivos. É a próxima etapa.

---

## ✔️ Confira

🖥️ **No seu terminal:**

<!-- rodar: shell -->
```bash
make conferir e=2
```

```
Conferindo a etapa 2 - Backup lógico

  ✅ dump em formato texto: /backup/dumps/liga_sudoers.sql
  ✅ dump em formato custom: /backup/dumps/liga_sudoers.dump
  ✅ dump em formato diretório: /backup/dumps/liga_sudoers_dir
  ✅ usuários e senhas: /backup/dumps/globais.sql
  ✅ itens_pedidos restaurada com chave primária, trigger e 2 chaves estrangeiras
  ✅ banco de cópia removido

✅ Etapa 2 conferida.
```

Saia do psql (`\q`) e do terminal do `primario` (`exit`).

---

# ➡️ Continue em [3. Backup físico](../03_backup_fisico/README.md)
