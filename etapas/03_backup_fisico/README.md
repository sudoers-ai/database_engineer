# 3️⃣ Backup físico

> ⬅️ Anterior: [2. Backup lógico](../02_backup_logico/README.md) · [README principal](../../README.md) · Etapa 3 de 10

> **A pergunta da diretoria:** "O disco do servidor morreu. A gente volta
> **inteiro**?"

O dump da etapa 2 recria o banco **comando por comando**. Funciona, mas num
banco grande leva horas: cada índice é reconstruído do zero. Quando o
servidor inteiro se perde, o que você quer é outra coisa: **uma cópia dos
arquivos**, pronta para ligar.

Isso é o **backup físico**. Nesta etapa você faz um, confere se ele está
íntegro e liga um servidor novo a partir dele.

---

## 3.1 Por que não um `cp` simples?

Na etapa 1 você viu que o banco é uma pasta de arquivos. Então bastaria
copiar a pasta? **Não com o banco ligado.** A cópia de 50 MB leva alguns
segundos e, durante esses segundos, o PostgreSQL continua escrevendo. O
arquivo da tabela `pedidos` seria copiado num instante e o do índice dela em
outro: a cópia sairia **incoerente**, um banco que nunca existiu.

O `pg_basebackup` resolve isso em três passos:

1. pede um **checkpoint** ao servidor e anota o LSN de início;
2. copia os arquivos (que ainda vão mudar durante a cópia, e tudo bem);
3. copia **também todo o WAL gerado durante a cópia**.

Ao ligar o servidor restaurado, ele reaplica esse WAL por cima dos arquivos e
chega a um estado coerente: o do fim do backup. É o mesmo mecanismo da
recuperação automática que você viu na etapa 1.

---

## 3.2 Fazendo o backup

🖥️ **No seu terminal:**

```bash
make bash n=primario
```

📦 **No terminal do `primario`:**

<!-- rodar: bash-primario -->
```bash
mkdir -p /backup/base
time pg_basebackup -U sudoers -D /backup/base/etapa3 -Fp -Xs -c fast -P
```

```
75025/75025 kB (100%), 1/1 tablespace

real	0m0.215s
...
```

| Opção | Significa |
|---|---|
| `-D /backup/base/etapa3` | a pasta de destino |
| `-Fp` | formato *plain*: uma pasta igual ao `PGDATA` |
| `-Xs` | copia o WAL gerado durante o backup, por *streaming* (passo 3) |
| `-c fast` | pede o checkpoint na hora, em vez de esperar o próximo |
| `-P` | mostra o progresso (uma linha só, que vai se atualizando até 100%) |

> O `pg_basebackup` usa o **protocolo de replicação**: ele conversa com o
> servidor do mesmo jeito que uma réplica vai conversar na etapa 5. Aqui, dentro
> do próprio servidor, a conexão local já tem permissão para isso.

---

## 3.3 O que tem dentro

<!-- rodar: bash-primario -->
```bash
ls /backup/base/etapa3
cat /backup/base/etapa3/backup_label
```

```
backup_label     global        pg_hba.conf    pg_notify     pg_stat      pg_twophase  postgresql.auto.conf
backup_manifest  pg_commit_ts  pg_ident.conf  pg_replslot   pg_stat_tmp  PG_VERSION   postgresql.conf
base             pg_dynshmem   pg_logical     pg_serial     pg_subtrans  pg_wal       pg_xact
...
START WAL LOCATION: 0/B000028 (file 00000001000000000000000B)
CHECKPOINT LOCATION: 0/B000080
BACKUP METHOD: streamed
BACKUP FROM: primary
START TIME: 2026-10-19 13:16:42 -03
LABEL: pg_basebackup base backup
START TIMELINE: 1
```

É a mesma estrutura do `PGDATA` que você explorou na etapa 1, com dois
arquivos a mais:

* **`backup_label`**: o "bilhete" do backup. Diz ao servidor que ligar com
  esta pasta: "você é um backup; comece a reaplicar o WAL a partir do LSN
  `START WAL LOCATION`". Sem ele, o servidor acharia que é um banco normal e
  ligaria incoerente.
* **`backup_manifest`**: a lista de **todos** os arquivos do backup, com
  tamanho e *checksum* de cada um.

---

## 3.4 O backup está íntegro?

Backup que nunca foi conferido é uma esperança, não um backup. O manifesto
existe para o `pg_verifybackup`:

<!-- rodar: bash-primario -->
```bash
pg_verifybackup /backup/base/etapa3
```

```
backup successfully verified
```

Agora estrague uma **cópia** do backup, de propósito, e veja o que acontece:

<!-- rodar: bash-primario -->
```bash
cp -a /backup/base/etapa3 /backup/base/adulterado
echo "lixo" >> /backup/base/adulterado/base/1/1259
pg_verifybackup /backup/base/adulterado || echo ">>> backup REPROVADO"
rm -rf /backup/base/adulterado
```

```
pg_verifybackup: error: "base/1/1259" has size 114693 on disk but size 114688 in the manifest
>>> backup REPROVADO
```

Um único arquivo com 5 bytes a mais e o backup é reprovado. Em produção,
quem roda o `pg_verifybackup` é o próprio script de backup, toda noite, e
alguém recebe um alerta se ele falhar.

---

## 3.5 Compactado

O formato *plain* é prático para restaurar, mas ocupa o tamanho do banco. Para
guardar, o normal é o formato *tar* compactado:

<!-- rodar: bash-primario -->
```bash
pg_basebackup -U sudoers -D /backup/base/etapa3_tar -Ft -z -Xs -c fast
ls -lh /backup/base/etapa3_tar
du -sh /backup/base/*
```

```
total 15M
-rw------- 1 postgres postgres 183K Oct 19 13:16 backup_manifest
-rw------- 1 postgres postgres  15M Oct 19 13:16 base.tar.gz
-rw------- 1 postgres postgres  17K Oct 19 13:16 pg_wal.tar.gz
89M	/backup/base/etapa3
15M	/backup/base/etapa3_tar
```

Seis vezes menor. Ele fica separado em `base.tar.gz` (os dados) e
`pg_wal.tar.gz` (o WAL gerado durante a cópia). Para restaurar, basta
descompactar os dois (o do WAL dentro de `pg_wal/`).

---

## 3.6 A vida segue

Depois do backup, alguém cadastra uma categoria nova.

🐘 **No psql do `primario`** (`make psql n=primario`):

<!-- rodar: primario -->
```sql
INSERT INTO categorias (descricao) VALUES ('Criada depois do backup físico');
SELECT count(*) AS categorias FROM categorias;
```

```
INSERT 0 1
 categorias
------------
         13
(1 row)
```

---

## 3.7 O disco morreu: restaurando em outro servidor

Não vamos destruir o `primario` (ele vai ser útil nas próximas etapas). Vamos
fazer o que se faz de verdade quando um servidor morre: **subir outro** a
partir do backup. Esse outro é o nó `restauracao`, que nasceu vazio.

🖥️ **No seu terminal:**

<!-- rodar: shell -->
```bash
make status
```

```
NÓ           SITUAÇÃO               PAPEL        TL  LSN          LÊ DE      RÉPLICAS PG
primario     no ar                  primário     1   0/D0025B0    -          0        17
replica1     esperando dados
replica2     esperando dados
restauracao  esperando dados
logico       no ar                  primário     1   0/1BA1FD8    -          0        18
```

Entre no `restauracao`. Ele está no ar, mas sem PostgreSQL rodando:

```bash
make bash n=restauracao
```

📦 **No terminal do `restauracao`:**

<!-- rodar: bash-restauracao -->
```bash
ls -A $PGDATA | wc -l
time cp -a /backup/base/etapa3/. $PGDATA/
ls $PGDATA | head -3
```

```
0

real	0m0.051s
...
backup_label
backup_manifest
base
```

A pasta estava vazia (zero arquivos) e agora tem o backup. Saia do terminal
do `restauracao` (`exit`) e reinicie o container, para o PostgreSQL subir com
a pasta preenchida.

🖥️ **No seu terminal:**

<!-- rodar: shell -->
```bash
make reiniciar n=restauracao
docker logs dbe_restauracao 2>&1 | grep -E "backup recovery|redo|ready to accept"
```

```
docker restart dbe_restauracao
dbe_restauracao
  ✅ restauracao pronto
LOG:  starting backup recovery with redo LSN 0/B000028, checkpoint LSN 0/B000080, on timeline ID 1
LOG:  redo starts at 0/B000028
LOG:  completed backup recovery with redo LSN 0/B000028 and end LSN 0/B000120
LOG:  redo done at 0/B000120 system usage: CPU: user: 0.00 s, system: 0.00 s, elapsed: 0.00 s
LOG:  checkpoint complete: wrote 3 buffers (0.0%); ...
LOG:  database system is ready to accept connections
```

O servidor leu o `backup_label`, reaplicou o WAL a partir do LSN de início e
ficou pronto. Confira o que ele tem:

🐘 **No psql do `restauracao`** (`make psql n=restauracao`):

<!-- rodar: restauracao -->
```sql
SELECT pg_is_in_recovery()                AS em_recuperacao,
       (SELECT count(*) FROM categorias)   AS categorias,
       (SELECT count(*) FROM pedidos)      AS pedidos;
```

```
 em_recuperacao | categorias | pedidos
----------------+------------+---------
 f              |         12 |  103017
(1 row)
```

* **`em_recuperacao = f`**: é um servidor normal, aceitando escrita. Se o
  `primario` tivesse morrido, bastaria apontar a aplicação para cá.
* **12 categorias**, e não 13: a categoria criada **depois** do backup não
  está aqui. O mesmo problema do dump: o RPO é o tempo desde o último backup.
* Os pedidos são exatamente os do momento do backup.

---

## 3.8 Lógico × físico

| | Lógico (`pg_dump`) | Físico (`pg_basebackup`) |
|---|---|---|
| Guarda | comandos SQL | os arquivos do servidor |
| Restaura | uma tabela, um banco | o **servidor inteiro** (todos os bancos e usuários) |
| RTO | lento: recria tabelas e índices | rápido: copiar e ligar |
| Entre versões do PostgreSQL | sim (17 → 18) | **não**: só a mesma versão |
| RPO | desde o último dump | desde o último backup |

Os dois têm o mesmo calcanhar de Aquiles: **tudo o que aconteceu depois do
backup se perde**. Mas repare numa diferença sutil: o backup físico já sabe
reaplicar WAL. Ele reaplicou o WAL **da cópia**. E se você guardasse **todo**
o WAL, desde o backup até agora? Aí daria para reaplicar até o último
segundo... ou até um segundo qualquer. É a próxima etapa.

---

## ✔️ Confira

🖥️ **No seu terminal:**

<!-- rodar: shell -->
```bash
make conferir e=3
```

```
Conferindo a etapa 3 - Backup físico

  ✅ backup físico em /backup/base/etapa3 (com backup_label e backup_manifest)
  ✅ backup compactado em /backup/base/etapa3_tar
  ✅ restauracao no ar, restaurado do backup e aceitando escrita
  ✅ restauracao tem 12 categorias e o primario 13: o backup é de antes da categoria nova

✅ Etapa 3 conferida.
```

---

# ➡️ Continue em [4. PITR](../04_pitr/README.md)
