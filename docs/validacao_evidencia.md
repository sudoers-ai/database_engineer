# 🔎 Guia de validação por evidências

> ⬅️ [README principal](../README.md)

"Rodou sem erro" não é evidência. Evidência é um **resultado que você
consegue mostrar** e que só existe se a etapa deu certo. Este guia diz, para
cada etapa, qual é esse resultado e como obtê-lo.

Regra geral: a partir da etapa 2, toda etapa tem um **comando de prova**,
`make conferir e=N`. Ele olha o **estado do cluster** (e não o que você
digitou), termina com ✅ ou diz exatamente o que falta, e pode ser rodado
quantas vezes você quiser: ele não altera nada.

| Etapa | Comando de prova | Evidência de sucesso |
|---|---|---|
| 0 | `make status` | `primario` e `logico` no ar; os outros três `esperando dados` |
| 1 | (perguntas do fim do roteiro) | você sabe explicar o WAL e o diagnóstico de RPO/RTO |
| 2 | `make conferir e=2` | 3 formatos de dump, `globais.sql`, `itens_pedidos` com PK, trigger e FKs |
| 3 | `make conferir e=3` | `restauracao` no ar, com 12 categorias contra 13 do `primario` |
| 4 | `make conferir e=4` | arquivamento sem falhas, `restauracao` na timeline 2, preços iguais |
| 5 | `make conferir e=5` | duas réplicas em *streaming*, slots ativos |
| 6 | `make conferir e=6` | as linhas de todos os testes síncronos nos três nós, cluster de volta ao assíncrono |
| 7 | `make conferir e=7` | `primario` na timeline 3, duas réplicas, nenhum registro de split-brain |
| 8 | `make conferir e=8` | `logico` (PG 18) com os pedidos, sequências sincronizadas, nenhum slot lógico |
| 9 | `make conferir e=9` | `pedidos` particionada, partição antiga arquivada, réplicas em dia |

---

## 0) Ambiente

```bash
make status
```

O `primario` e o `logico` com `no ar`; `replica1`, `replica2` e
`restauracao` com `esperando dados`. "Esperando dados" **não é erro**: esses
nós nascem vazios de propósito.

## 1) Conhecer o primário

Não há comando de prova: a etapa não muda nada de importante no banco. A
evidência é você responder sem consultar:

* onde fica o arquivo da tabela `pedidos`, e o que é o `pg_wal/`;
* por que o `archive_mode` exige reiniciar e o `checkpoint_timeout` não;
* por que a linha gravada antes do `docker kill` sobreviveu.

## 2) Backup lógico

```bash
make conferir e=2
```

O que essa conferência garante: os dumps existem em `/backup/dumps` nos três
formatos, os usuários foram salvos, e a `itens_pedidos` voltou **completa**
(chave primária, trigger e chaves estrangeiras). Se ela tivesse voltado com
`pg_restore -t`, a conferência acusaria.

Evidência complementar (o RPO do dump):

```bash
docker exec dbe_primario psql -U sudoers -d liga_sudoers -c \
  "SELECT count(*) FROM pedidos p WHERE NOT EXISTS (SELECT 1 FROM itens_pedidos i WHERE i.id_pedido = p.id)"
```

Em torno de mil: as vendas de depois do dump.

## 3) Backup físico

```bash
make conferir e=3
```

Evidência complementar (o log da restauração):

```bash
docker logs dbe_restauracao 2>&1 | grep -E "backup recovery|ready to accept"
```

## 4) PITR

```bash
make conferir e=4
```

O que essa conferência garante: o arquivamento está ligado **e sem falhas**,
o `restauracao` saiu de um PITR (timeline 2) num ponto anterior ao bug, os
preços da produção são iguais aos dele, e a produção tem **mais** pedidos
que ele (as vendas de depois do bug não foram perdidas).

Evidência complementar (onde a recuperação parou):

```bash
docker logs dbe_restauracao 2>&1 | grep "recovery stopping"
```

## 5) Replicação assíncrona

```bash
make conferir e=5
make status
```

No `make status`: as duas réplicas com `PAPEL = réplica`, `LÊ DE = primario`
e o mesmo LSN do primário; o primário com `RÉPLICAS = 2`.

Evidência complementar (a réplica é somente leitura):

```bash
docker exec dbe_replica1 psql -U sudoers -d liga_sudoers -c "INSERT INTO categorias (descricao) VALUES ('x')"
```

Tem que dar `ERROR: cannot execute INSERT in a read-only transaction`.

## 6) Replicação síncrona

```bash
make conferir e=6
```

A linha `sincrono, nenhuma replica no ar` presente nos três nós é a prova de
que você viu o COMMIT pendurar, cancelou, e a transação ficou gravada no
primário (e depois chegou às réplicas).

## 7) Failover e switchover

```bash
make conferir e=7
make status
```

No `make status`: o `primario` como primário na **timeline 3**.

Evidência complementar (a história das timelines):

```bash
docker exec dbe_primario bash -c 'cat $PGDATA/pg_wal/00000003.history'
```

Duas linhas: a saída da timeline 1 (o failover) e a saída da timeline 2 (o
switchover).

## 8) Replicação lógica

```bash
make conferir e=8
```

O último item ("ensaio desmontado") é o mais importante na vida real: nenhum
slot lógico esquecido no primário.

## 9) Particionamento

```bash
make conferir e=9
```

Evidência complementar (o *pruning*):

```bash
docker exec dbe_primario psql -U sudoers -d liga_sudoers -c \
  "EXPLAIN SELECT count(*) FROM pedidos WHERE dt_venda >= date_trunc('month', now())"
```

O plano tem que mostrar `Subplans Removed` ou só as partições a partir do
mês atual.

---

## Se a conferência falhar

Cada linha ❌ diz **o que** falta e **em que seção** do roteiro. Corrija e
rode de novo. Se não entender a mensagem, veja o [❓ FAQ](./faq.md) ou rode
`make diagnostico` e mande a saída ao instrutor.
