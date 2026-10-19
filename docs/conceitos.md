# 🧠 Conceitos: WAL, backup e replicação

> ⬅️ [README principal](../README.md)

Os roteiros das etapas explicam cada comando no momento em que ele aparece.
Este texto faz o contrário: junta as ideias num lugar só, para você enxergar
o desenho inteiro. Leia antes de começar, ou depois da etapa 9, para
consolidar.

---

## 1. Tudo começa no WAL

Um banco de dados promete uma coisa difícil: **depois do COMMIT, o dado não
se perde**. O PostgreSQL cumpre a promessa com o **WAL** (*Write-Ahead
Log*): antes de mudar qualquer página de tabela ou índice, ele escreve num
diário, sequencial, **o que vai mudar**, e só responde COMMIT depois que esse
registro está no disco.

As páginas de dados de verdade são gravadas depois, com calma, no
**checkpoint**. Se o servidor cair antes disso, ao religar ele relê o WAL
desde o último checkpoint e refaz o que faltava (a **recuperação de queda**,
*crash recovery*). Você viu isso na [etapa 1](../etapas/01_primario/README.md).

```
  INSERT ──► WAL (disco, sequencial) ──► COMMIT ──► ... ──► checkpoint ──► tabela (disco)
               │
               └── tudo o que vem depois "lê" este diário:
                   backup físico, PITR, réplica física, replicação lógica
```

Cada posição do WAL tem um endereço que só cresce, o **LSN** (`0/705E348`). O
WAL é guardado em arquivos de 16 MB, os **segmentos**, cujo nome começa pela
**timeline** (`00000001...`).

A sacada que organiza a disciplina inteira: **o WAL é uma descrição completa
de tudo o que aconteceu com o banco**. Quem tem uma cópia dos arquivos de
algum momento **e** o WAL desde então consegue reconstruir o banco em
qualquer instante posterior. Backup físico, PITR e replicação física são três
jeitos de usar essa mesma ideia.

---

## 2. RPO e RTO: a régua de tudo

Toda decisão desta disciplina se mede com duas perguntas:

* **RPO** (*Recovery Point Objective*): quanto dado se aceita perder? É a
  distância entre o desastre e o último ponto que você consegue recuperar.
* **RTO** (*Recovery Time Objective*): quanto tempo se aceita ficar fora? É
  o tempo entre o desastre e o sistema de volta.

| Técnica | RPO típico | RTO típico | Protege contra |
|---|---|---|---|
| Nada (só o WAL local) | zero numa queda de energia; **tudo** se o disco morrer | segundos / para sempre | queda de energia |
| Backup lógico diário | até 24 h | horas (recria tabelas e índices) | erro humano, migração de versão |
| Backup físico diário | até 24 h | o tempo de copiar | perda do servidor |
| Backup físico + arquivo de WAL (PITR) | segundos (`archive_timeout`) | copiar + reaplicar WAL: minutos a horas | perda do servidor **e** erro humano |
| Réplica assíncrona | milissegundos (o atraso) | segundos (promover) | perda do servidor |
| Réplica síncrona | **zero** | segundos (promover) | perda do servidor sem perder transação confirmada |

Repare que **nenhuma linha resolve tudo**. A réplica tem o melhor RPO e RTO,
mas não protege contra um `DROP TABLE`. O PITR protege contra o `DROP TABLE`,
mas demora. Por isso um ambiente sério combina **as duas famílias**.

---

## 3. Backup

### Lógico × físico

| | Lógico (`pg_dump`) | Físico (`pg_basebackup`) |
|---|---|---|
| O que guarda | comandos SQL (`CREATE`, `COPY`) | os arquivos do `PGDATA` |
| Escopo | um banco (usuários à parte, com `pg_dumpall --globals-only`) | o servidor inteiro |
| Restaura uma tabela só | sim (`pg_restore -L`) | não diretamente |
| Entre versões | sim | não |
| Velocidade de restauração | lenta: recria cada índice | rápida: copiar e ligar |
| Serve de base para PITR | não | **sim** |

### Contínuo (PITR)

Backup físico + **arquivamento de WAL**: todo segmento fechado é copiado
pelo `archive_command` para um storage separado. Para restaurar, liga-se o
backup com um `restore_command` (o caminho inverso) e um **alvo**
(`recovery_target_time`, `_name`, `_xid`, `_lsn`). O servidor reaplica o WAL
até o alvo e para.

### Regras que não mudam

* **Backup no mesmo disco não é backup.** A regra clássica é a **3-2-1**: 3
  cópias, em 2 tipos de mídia, 1 fora do local.
* **Backup que nunca foi restaurado é uma esperança.** Verifique
  (`pg_verifybackup`) e, de tempos em tempos, restaure de verdade.
* **Monitore o arquivamento.** Se o `archive_command` falhar, o PostgreSQL
  não apaga o WAL: o `pg_wal/` cresce até o disco acabar.
* Em produção, use uma ferramenta feita para isso: **pgBackRest**, **Barman**
  ou **WAL-G**. Elas fazem backups full, diferencial e incremental,
  paralelismo, compressão, criptografia, retenção e verificação. Mas o que
  elas fazem por baixo é exatamente o que você fez nas etapas 3 e 4.

---

## 4. Replicação

### Física × lógica

| | Física (*streaming replication*) | Lógica (*publication/subscription*) |
|---|---|---|
| O que trafega | o WAL cru: "mude estes bytes desta página" | o WAL decodificado: "insira esta linha nesta tabela" |
| Escopo | o servidor inteiro | as tabelas (e colunas, e linhas) escolhidas |
| Versões | iguais | podem ser diferentes |
| Destino | somente leitura (*hot standby*) | aceita escrita |
| DDL e sequências | replicados | **não** replicados |
| `wal_level` | `replica` | `logical` |
| Para que serve | alta disponibilidade, leitura escalável | migração de versão, alimentar BI, consolidar bancos |

### Síncrona × assíncrona

Na **assíncrona**, o primário responde COMMIT sem esperar a réplica. Rápido,
mas existe uma janela em que a transação confirmada só está no primário.

Na **síncrona**, o primário espera uma confirmação. **Quem** confirma é o
`synchronous_standby_names` (`FIRST 1 (a, b)`, `ANY 1 (a, b)`); **o quê** é
o `synchronous_commit`:

```
 off ─── local ─── remote_write ─── on ─── remote_apply
  │        │            │            │           │
 memória  disco do   memória da   disco da   reaplicado e
 do       primário    réplica     réplica    visível na réplica
 primário
                 ◄── mais rápido          mais seguro ──►
```

Duas armadilhas da síncrona (ambas vistas na [etapa 6](../etapas/06_replicacao_sincrona/README.md)):

1. sem nenhuma réplica que possa confirmar, **as escritas param**. Por isso
   se usa `FIRST 1` ou `ANY 1` com **duas** réplicas ou mais;
2. não é uma transação distribuída: o primário grava e **depois** espera. Se a
   espera for cancelada, o dado fica só no primário.

### Slots

Um *replication slot* faz o primário guardar o WAL que um consumidor (réplica
física ou assinatura lógica) ainda não recebeu. Sem slot, uma réplica que
fica fora tempo demais perde o WAL de que precisa. Com slot, um consumidor
que **nunca volta** faz o primário guardar WAL para sempre. Monitore
(`pg_replication_slots`) e limite (`max_slot_wal_keep_size`).

---

## 5. Alta disponibilidade × recuperação de desastre

São problemas diferentes, e confundi-los é o erro mais caro desta área.

| | Alta disponibilidade (HA) | Recuperação de desastre (DR) |
|---|---|---|
| Pergunta | "o servidor caiu, quem assume?" | "perdemos os dados (ou o data center), como voltamos?" |
| Ferramenta | réplicas + failover | backup + PITR, em outro lugar |
| Protege contra erro humano? | **não**: a réplica repete o erro | **sim** |

> **Réplica não é backup.** Um `DROP TABLE` chega às réplicas em
> milissegundos.

---

## 6. Timelines

Toda vez que um servidor deixa de seguir a história que estava reaplicando e
começa a escrever a sua própria (ao fim de um PITR, ou numa promoção de
réplica), ele abre uma **nova timeline** e grava um arquivo
`0000000N.history` dizendo de onde ela saiu.

```
 TL 1 ──────────●──────────────────────►  (o primário antigo continuaria aqui)
                │ promoção / fim do PITR
 TL 2           └──────────────────────►  (a nova história)
```

As timelines existem para que duas histórias diferentes **nunca se misturem**
no arquivo de WAL e para que as réplicas saibam seguir uma promoção
(`recovery_target_timeline = 'latest'`).

---

## 7. Failover, switchover e split-brain

* **Failover**: troca **não planejada**. O primário morreu; promove-se uma
  réplica. Pode perder o que não tinha chegado à réplica (no assíncrono).
* **Switchover**: troca **planejada**. O primário é desligado com calma (e
  envia todo o WAL pendente), uma réplica é promovida. Não perde nada.
* **Split-brain**: dois servidores aceitando escrita ao mesmo tempo. Gera
  dados conflitantes que **não têm conserto automático**. Evita-se com
  *fencing*: garantir que o antigo primário não volta como primário.
* **`pg_rewind`**: traz o antigo primário de volta como réplica, copiando só
  os blocos que divergiram. Exige `data_checksums` ou `wal_log_hints`.

Em produção, quem orquestra tudo isso é uma ferramenta (Patroni, repmgr,
pg_auto_failover). Ela faz em segundos o que você fez à mão na
[etapa 7](../etapas/07_failover/README.md).

---

## 8. Particionamento

Dividir uma tabela grande em partições menores, por uma chave:

| Tipo | Divide por | Bom para |
|---|---|---|
| `RANGE` | faixas (datas) | dado que envelhece: pedidos, logs, eventos |
| `LIST` | valores exatos | categorias fixas: país, canal |
| `HASH` | resto de uma conta | espalhar escrita por igual |

**Ganha-se:** consultas que filtram pela chave leem só as partições
necessárias (*partition pruning*); apagar dados antigos vira `DROP TABLE`;
manutenção por partição.

**Paga-se:** a chave primária precisa incluir a chave de particionamento, o
que dificulta as chaves estrangeiras que apontam para a tabela; consultas que
**não** filtram pela chave visitam todas as partições; alguém precisa criar
as partições futuras.

**Quando não particionar:** tabela que cabe confortavelmente na memória,
sem padrão de acesso por faixa, ou sem política de retenção. Um índice bem
escolhido resolve a maioria dos problemas de "tabela grande" antes de o
particionamento ser necessário.

---

## 9. Qual ferramenta para qual pergunta

| A pergunta | A resposta | Etapa |
|---|---|---|
| "Apagaram uma tabela" | backup lógico (restaurar só ela) ou PITR num servidor à parte | 2, 4 |
| "Perdemos o servidor" | backup físico + WAL, ou promover uma réplica | 3, 4, 7 |
| "Um `UPDATE` errado às 14h03" | PITR até 14h02, num servidor à parte, e copiar de volta só o que estragou | 4 |
| "Não podemos ficar fora" | réplicas + failover automático | 5, 7 |
| "Não podemos perder transação confirmada" | replicação síncrona com 2+ réplicas | 6 |
| "Migrar de versão sem parar" | replicação lógica | 8 |
| "O BI está pesando no transacional" | réplica física (leitura) ou lógica (só as tabelas dele) | 5, 8 |
| "A tabela não para de crescer" | particionamento + retenção | 9 |
