# 🧪 Desafios — Database Engineering

> ⬅️ Anterior: [9. Particionamento](../etapas/09_particionamento/README.md) · [README principal](../README.md) · Etapa 10 de 10

A trilha guiada acabou. Aqui não há passo a passo: há o problema, o que conta
como evidência e o que entregar.

Escolha o seu nível. Cada desafio tem **tarefas**, **evidências** (o que
comprova que deu certo) e **entregáveis** (o que você vai postar ou commitar).

- [Nível Júnior](#-nível-júnior) — a trilha de ponta a ponta, explicada com as suas palavras
- [Nível Pleno](#-nível-pleno) — os mesmos problemas, sem roteiro e com as variações do mundo real
- [Nível Sênior](#-nível-sênior) — as ferramentas de produção, automação e o plano de continuidade

> **Dica:** conclua o Júnior antes, mesmo que você seja avançado. Ele garante
> que o ambiente está consistente, e os outros níveis partem dele.
>
> **Onde colocar o seu trabalho:** crie uma pasta `entregas/` na raiz do
> repositório. Não é preciso alterar nenhum arquivo do projeto. Para rodar um
> SQL seu: `make sql n=primario f=entregas/arquivo.sql`.
>
> **Quer recomeçar do zero?** `make limpar && make subir`. Para pular direto
> para as etapas 6 ou 7: `make gabarito-replicas`.

---

## 🔹 Nível Júnior

**Foco:** percorrer a trilha inteira e provar que entendeu o porquê de cada
passo.

### Tarefas

1. Concluir as etapas 1 a 9 **sem usar o `make gabarito-replicas`**.
2. Rodar `make conferir e=N` para as etapas 2 a 9 e guardar a saída.
3. Refazer o **diagnóstico da etapa 1** com o cluster que você montou: para
   cada cenário (queda de energia, tabela apagada, disco perdido, servidor
   destruído, `UPDATE` errado), escreva o **RPO** e o **RTO** de agora, e
   **qual etapa** garante cada número.
4. Explicar, com as suas palavras e em no máximo cinco linhas cada:
   * por que réplica não é backup (etapa 5);
   * o que é uma timeline e por que ela muda no PITR e na promoção (etapas 4 e 7);
   * por que o `id` pulou de 1 para 34 depois do failover (etapa 7);
   * o que aconteceria se o servidor restaurado na etapa 4 continuasse com
     `archive_mode = on`.
5. Desenhar (pode ser à mão, no Excalidraw ou em ASCII) o cluster no fim da
   etapa 9: os cinco nós, quem replica de quem, por qual tipo de replicação,
   e onde ficam os backups.

### Evidências mínimas

* Saída de `make conferir e=2` até `make conferir e=9`, todas com ✅.
* Saída de `make status` no fim da trilha (primário na timeline 3, duas réplicas).
* *Print* do log com `recovery stopping at restore point` (etapa 4).
* *Print* do `pg_rewind` com `servers diverged at WAL location` (etapa 7).

### Entregáveis

* `entregas/CHECKLIST_JUNIOR.md` — o [checklist](../docs/checklist.md) preenchido.
* `entregas/DIAGNOSTICO.md` — a tabela da tarefa 3 e as respostas da tarefa 4.
* `entregas/cluster.png` (ou `.md`) — o desenho da tarefa 5.

---

## 🔸 Nível Pleno

**Foco:** resolver os mesmos problemas sem o roteiro, nas variações que
aparecem de verdade.

### Tarefas

**1. PITR pela hora, sem ponto de restauração.**
Ninguém marcou `pg_create_restore_point` antes do incidente. Faça um backup
base novo, rode `make carga`, anote a hora, rode um `DELETE FROM
itens_pedidos WHERE id_produto = 7;` "acidental" e rode mais carga. Recupere
os itens do produto 7 no nó `restauracao` usando **`recovery_target_time`**
e **`recovery_target_action = 'pause'`**: confira os dados com o servidor
pausado antes de promover. Devolva os itens à produção sem perder a carga de
depois do `DELETE`.

**2. Backup automatizado, com retenção e teste.**
Escreva `entregas/backup.sh`, que roda dentro do `primario` e:
* faz um `pg_basebackup` compactado numa pasta com a data no nome;
* roda o `pg_verifybackup` e **falha** se a verificação falhar;
* mantém só os **3** backups mais recentes;
* apaga do `/backup/wal` os segmentos mais antigos que o backup mais antigo
  mantido (dica: `pg_archivecleanup` e o arquivo `.backup`).

Prove que ele funciona rodando-o três vezes e mostrando a retenção. Depois,
**restaure o backup mais antigo** no `restauracao`. Backup que nunca foi
restaurado não é backup.

**3. Menor privilégio contra o estagiário.**
O estagiário da etapa 2 conseguiu apagar uma tabela porque usava o
`sudoers`. Crie os perfis `app_loja` (lê e grava nas tabelas, sem `DROP`
nem `TRUNCATE`), `bi_leitura` (só `SELECT`) e um usuário para cada um. Prove
que `app_loja` consegue vender (rode o `pgbench` da `make carga` com ele) e
**não** consegue `DROP TABLE`. Lembre que usuários **não** vão no `pg_dump`.

**4. Replicação lógica com filtro de linha e de coluna (LGPD).**
O time de BI quer a `auditoria_pedidos` no `logico`, mas **sem o telefone** e
**só dos pedidos feitos em aparelhos móveis**. Crie uma publicação com
**lista de colunas** e **filtro de linhas** (`WHERE`). Mostre no `logico`
que a coluna não existe e que só chegam as linhas do filtro.

**5. Chave estrangeira com tabela particionada.**
Na etapa 9 você removeu as chaves estrangeiras de `itens_pedidos` e
`auditoria_pedidos` para `pedidos`. Traga a integridade de volta: leve
`dt_venda` para `itens_pedidos`, crie a chave estrangeira **composta**
`(id_pedido, dt_venda) → pedidos (id, dt_venda)` e ajuste o
`carga/vendas.sql` (uma cópia em `entregas/`) para gravar o novo campo. Prove
que um item com pedido inexistente é recusado.

**6. Partições criadas sozinhas.**
Escreva uma função `criar_particoes(meses_a_frente int)` que cria as
partições que faltam até N meses no futuro e **não falha** se já existirem.
Prove que ela é idempotente (rode duas vezes). Depois, simule o esquecimento:
insira um pedido de daqui a 6 meses, veja-o cair na `pedidos_default` e
descubra por que a função passa a falhar para aquele mês. Escreva o
procedimento de correção.

**7. O teto do slot.**
Configure `max_slot_wal_keep_size = '64MB'`, desligue a `replica2`, rode
carga até passar do teto e mostre o slot com `wal_status = 'lost'`. Explique
o que aconteceu com a `replica2` ao ser ligada e recupere-a.

### Evidências mínimas

* Log com `recovery stopping before ... time` e a contagem dos itens do
  produto 7 antes e depois (tarefa 1).
* Três execuções do `backup.sh`, a listagem com só três backups e o
  `restauracao` no ar a partir do mais antigo (tarefa 2).
* `ERROR: must be owner of table` para o `app_loja` (tarefa 3).
* `\d auditoria_pedidos` no `logico`, sem `telefone` (tarefa 4).
* `ERROR: insert or update on table "itens_pedidos" violates foreign key constraint` (tarefa 5).
* `wal_status = lost` no `pg_replication_slots` (tarefa 7).

### Entregáveis

* `entregas/pitr_por_hora.md`, `entregas/backup.sh`, `entregas/privilegios.sql`,
  `entregas/publicacao_lgpd.sql`, `entregas/fk_particionada.sql`,
  `entregas/criar_particoes.sql` e `entregas/slot_perdido.md`.
* Um `entregas/PLENO.md` com o *print* de cada evidência e, em cada tarefa,
  um parágrafo: "o que eu faria diferente em produção?".

---

## 🔺 Nível Sênior

**Foco:** as ferramentas que a indústria usa, automação e o plano que a
empresa segue quando tudo dá errado. Aqui você pode (e deve) acrescentar
serviços ao ambiente: crie um `entregas/docker-compose.override.yml`.

### Tarefas

**1. pgBackRest no lugar dos scripts.**
Suba um repositório pgBackRest (num container novo ou no próprio
`primario`), configure o `archive_command` para ele e faça um backup
**full**, um **diferencial** e um **incremental**. Restaure no
`restauracao` com PITR por hora usando o `pgbackrest restore --type=time`.
Compare, numa tabela, com o que você fez à mão nas etapas 3 e 4: tamanho,
tempo de backup, tempo de restauração, paralelismo, verificação e retenção.

**2. Failover automático.**
Substitua o seu "eu olho o `make status` e promovo" por uma ferramenta:
**Patroni** (com etcd) ou **pg_auto_failover**. Derrube o primário com
`docker kill` e meça o RTO real (do `kill` até a primeira venda aceita de
novo, com a carga rodando o tempo todo). Mostre como a ferramenta evita o
split-brain da etapa 7.

**3. A aplicação não pode saber quem é o primário.**
Coloque um **PgBouncer** (ou HAProxy) na frente do cluster e rode a carga
através dele. Faça um switchover e mostre que a carga continua sem trocar a
configuração dela. Compare com a solução do driver da etapa 7
(`target_session_attrs=read-write`): o que cada uma resolve e o que não
resolve.

**4. O custo real da replicação síncrona.**
Na etapa 6 as réplicas estavam a 0,1 ms de distância. Use o `tc netem`
(num container com `cap_add: NET_ADMIN`) para simular **2 ms, 20 ms e 80 ms**
de latência até as réplicas. Meça o TPS com `synchronous_commit` em `off`,
`local`, `on` e `remote_apply` em cada latência e monte o gráfico. Com base
nele, escreva a recomendação para a Liga Sudoers: quais réplicas síncronas,
onde, e com qual `synchronous_standby_names`.

**5. Achar o culpado no WAL.**
Repita o desastre da etapa 4 sem ponto de restauração e **sem saber a hora**.
Use o `pg_waldump` sobre o arquivo de WAL para encontrar a transação do
`UPDATE produtos` (dica: o `relfilenode` da tabela e o registro `COMMIT`) e
recupere com **`recovery_target_xid`** e **`recovery_target_inclusive = off`**.

**6. A virada de versão, de verdade.**
Faça a migração ensaiada na etapa 8 até o fim, com a carga rodando: o
`logico` vira a produção. Meça a janela de indisponibilidade (do momento em
que as escritas param até a primeira venda no PostgreSQL 18). Liste tudo o
que não vem pela replicação lógica e que você precisou levar à mão (dica:
sequências, usuários, `GRANT`s, a coluna nova, as tabelas fora da
publicação).

**7. O runbook.**
Escreva o **plano de continuidade** da Liga Sudoers: um documento que um
plantonista, às 3h da manhã, consiga seguir sem você. Para cada cenário
(primário caiu; réplica caiu; disco do arquivo de WAL cheio; arquivamento
falhando; `DELETE` errado; slot órfão enchendo o disco; split-brain), escreva:
como **detectar** (qual consulta ou alerta), como **decidir**, os
**comandos** exatos e como **validar** que voltou. Teste cada procedimento no
cluster.

### Evidências mínimas

* `pgbackrest info` mostrando os três tipos de backup e o log do restore
  por hora (tarefa 1).
* O RTO medido, com o trecho da saída da carga mostrando a interrupção e a
  volta (tarefa 2).
* A carga rodando através do PgBouncer durante um switchover, sem erros
  (tarefa 3).
* O gráfico TPS × latência × `synchronous_commit` (tarefa 4).
* A linha do `pg_waldump` com o `xid` culpado e o log `recovery stopping
  before commit of transaction` (tarefa 5).
* A janela de indisponibilidade medida (tarefa 6).

### Entregáveis

* `entregas/docker-compose.override.yml` com os serviços que você acrescentou.
* `entregas/SENIOR.md` com as evidências, as tabelas comparativas e as
  recomendações.
* `entregas/RUNBOOK.md` — o plano de continuidade da tarefa 7.

---

## 📤 Como entregar

1. Faça um *fork* deste repositório.
2. Coloque tudo em `entregas/`.
3. Abra um *pull request* para o seu próprio *fork* (ou envie o link) com o
   título `Desafio <nível> - <seu nome>`.
4. Poste no LinkedIn o que você aprendeu, com o *print* de que mais se
   orgulha, e marque a Sudoers.

---

# 🏁 Fim da trilha. Volte ao [README principal](../README.md)
