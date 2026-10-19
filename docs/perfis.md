# 👩‍💻 Perfis e responsabilidades

> ⬅️ [README principal](../README.md)

Nesta disciplina você faz, sozinho, o trabalho de vários profissionais. Num
time de verdade eles são pessoas diferentes, e saber onde termina o trabalho
de um e começa o do outro é parte de ser sênior.

> **Dica:** ao fim de cada etapa, pergunte-se: "quem do time teria feito
> isto? E quem teria que ser avisado?"

---

## Database Administrator (DBA)

Cuida do **servidor de banco** no dia a dia: é quem está de plantão quando
ele cai.

**Responsabilidades:**

* Instalar, configurar e atualizar o PostgreSQL.
* Garantir que os backups rodam, estão íntegros e **restauram**.
* Monitorar espaço em disco, arquivamento, replicação e slots.
* Atender incidentes: restaurar dados, promover réplicas, recuperar o
  cluster.
* Controlar acessos (usuários, `GRANT`s, `pg_hba.conf`).

**Onde aparece na trilha:**

| Etapa | O que o DBA faz |
|---|---|
| 1 | Examina o servidor antes de mexer em qualquer coisa |
| 2 e 4 | Restaura a tabela apagada e os preços estragados, sem perder as vendas |
| 5 | Monitora o atraso das réplicas e o WAL retido pelos slots |
| 7 | Faz o failover às 3h da manhã |

**A pergunta que ele sempre faz:** "se isto der errado agora, eu consigo
voltar?"

---

## Database Engineer (DBE)

O título desta disciplina. Enquanto o DBA **opera**, o DBE **projeta e
automatiza** a plataforma de banco de dados: a arquitetura, as ferramentas e
os processos que fazem o DBA dormir tranquilo.

**Responsabilidades:**

* Desenhar a topologia: quantas réplicas, síncronas ou não, onde ficam.
* Definir, junto com o negócio, o **RPO e o RTO** de cada sistema, e
  construir o que os garante.
* Automatizar backup, verificação, retenção, failover e criação de partições.
* Planejar crescimento: particionamento, retenção, capacidade.
* Planejar e executar migrações de versão com o mínimo de indisponibilidade.

**Onde aparece na trilha:**

| Etapa | O que o DBE faz |
|---|---|
| 1 | Traduz "quanto perdemos?" em RPO e RTO |
| 4 | Decide o `archive_timeout` (o RPO) e a frequência do backup base (o RTO) |
| 6 | Mede o custo da replicação síncrona e recomenda `ANY 1` de 2 |
| 8 | Planeja a migração 17 → 18 com replicação lógica |
| 9 | Escolhe a chave de particionamento e a política de retenção |

**A pergunta que ele sempre faz:** "isso escala, e funciona sem mim?"

---

## Site Reliability Engineer (SRE) / Engenharia de Plataforma

Cuida da confiabilidade do **sistema inteiro**, do qual o banco é uma peça.

**Responsabilidades:**

* Alertas e painéis: atraso de réplica, arquivamento falhando, disco enchendo.
* Ferramentas de alta disponibilidade (Patroni, pg_auto_failover) e o
  roteamento das conexões (PgBouncer, HAProxy, DNS).
* Testes de desastre periódicos ("game days") e o *runbook* de incidentes.

**Onde aparece na trilha:**

| Etapa | O que o SRE faz |
|---|---|
| 4 | Cria o alerta para `pg_stat_archiver.failed_count > 0` |
| 5 e 8 | Cria o alerta para slot inativo retendo WAL |
| 7 | Automatiza o failover e o *fencing*; garante que a aplicação ache o novo primário |

**A pergunta que ele sempre faz:** "como eu fico sabendo **antes** do
cliente?"

---

## Desenvolvedor (Dev)

Escreve a aplicação que usa o banco. Suas decisões afetam diretamente o
trabalho dos outros três.

**Onde aparece na trilha:**

| Etapa | O que o Dev precisa saber |
|---|---|
| 4 | Fazer `pg_create_restore_point` antes de um deploy é de graça e salva o dia |
| 6 | `SET synchronous_commit` por transação: `remote_apply` para "ler o que acabei de gravar" numa réplica, `local` para logs |
| 7 | Conectar com vários hosts e `target_session_attrs=read-write`; não depender de `id` sem buracos |
| 8 | Toda mudança de estrutura (`ALTER TABLE`) precisa ser combinada com o DBE quando há replicação lógica |
| 9 | Consultas sem filtro pela chave de particionamento ficam mais lentas |

**A pergunta que ele deveria fazer:** "o que essa mudança faz com o banco em
produção?"

---

## Segurança e Privacidade (DPO / LGPD)

Garante que dado pessoal só vai para onde precisa ir, e que o acesso é o
mínimo necessário.

**Onde aparece na trilha:**

| Etapa | O que a área de segurança exige |
|---|---|
| 2 | Backups são cópias completas de dado pessoal: precisam de criptografia e controle de acesso |
| 5 | O usuário de replicação não é superusuário; senhas em `.pgpass`, nunca na linha de comando |
| 8 | A `auditoria_pedidos` (com telefones) fica fora da publicação para o BI |

**A pergunta que ela sempre faz:** "quem pode ver isto, e por quê?"
