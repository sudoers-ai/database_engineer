# 🐘 Liga Sudoers — Database Engineering

> Você só precisa de Docker: tudo roda em containers na sua máquina.

Bem-vindo ao **Database Engineering**. Este é um laboratório 100% prático:
você recebe o banco de produção da Liga Sudoers, com 18 meses de vendas,
rodando num único servidor, sem backup e sem réplica. Se o disco morrer hoje, a empresa acaba.

O seu trabalho é transformar esse servidor solitário num cluster que
sobrevive a erro humano, a queda de servidor e ao próprio crescimento.

---

## 🎯 O que você vai aprender

Não é "decorar `pg_dump`". É saber responder, com números, as duas perguntas
que todo DBE ouve um dia:

| Pergunta | Nome técnico | Exemplo |
|---|---|---|
| "Se der problema, **quanto dado** a gente perde?" | **RPO** (*Recovery Point Objective*) | "perdemos no máximo 1 minuto de vendas" |
| "Se der problema, **quanto tempo** a gente fica fora?" | **RTO** (*Recovery Time Objective*) | "voltamos em 30 segundos" |

Ao final você terá feito, com as próprias mãos:

* **backup lógico** (`pg_dump`, `pg_restore`) e restauração de uma tabela só;
* **backup físico** (`pg_basebackup`) e a restauração de um servidor inteiro;
* **arquivamento de WAL** e **restauração point-in-time (PITR)**: voltar o
  banco para o segundo antes de um `UPDATE` desastroso;
* **replicação física assíncrona** com duas réplicas e *replication slots*;
* **replicação síncrona** (`FIRST`, `ANY`, `remote_apply`) e o preço dela;
* **failover**, **split-brain**, **timelines**, `pg_rewind` e **switchover**;
* **replicação lógica** para um PostgreSQL de versão mais nova (17 → 18);
* **particionamento** de uma tabela de 150 mil pedidos, sem perder venda.

---

## 📨 As perguntas da diretoria

A Liga Sudoers cresceu. O CTO trouxe para você a lista que tira o sono dele.
Cada pergunta vira uma etapa da trilha:

| # | A pergunta | Onde você responde |
|---|---|---|
| 1 | "Alguém apagou uma tabela. A gente consegue voltar?" | [2. Backup lógico](./etapas/02_backup_logico/README.md) |
| 2 | "O disco do servidor morreu. A gente volta **inteiro**?" | [3. Backup físico](./etapas/03_backup_fisico/README.md) |
| 3 | "Um `UPDATE` errado rodou às 14h03. Dá para voltar às 14h02?" | [4. PITR](./etapas/04_pitr/README.md) |
| 4 | "O servidor caiu. Quanto tempo ficamos fora?" | [5. Réplicas](./etapas/05_replicacao_assincrona/README.md) e [7. Failover](./etapas/07_failover/README.md) |
| 5 | "Podemos perder uma venda que o cliente viu confirmada?" | [6. Replicação síncrona](./etapas/06_replicacao_sincrona/README.md) |
| 6 | "Dá para migrar para o PostgreSQL 18 sem parar a loja?" | [8. Replicação lógica](./etapas/08_replicacao_logica/README.md) |
| 7 | "A tabela de pedidos não para de crescer. E agora?" | [9. Particionamento](./etapas/09_particionamento/README.md) |

---

## 🏗️ O cluster que você vai operar

Cinco servidores PostgreSQL, cada um num container, todos na mesma rede:

```
                         ┌──────────────────────────┐
     make carga ───────► │  primario   (PG 17)      │  produção: 100 mil pedidos
     (vendas)            │  localhost:5460          │
                         └────────────┬─────────────┘
                     WAL (etapa 5)    │       replicação lógica (etapa 8)
               ┌──────────────────────┼─────────────────────────┐
               ▼                      ▼                         ▼
   ┌───────────────────┐  ┌───────────────────┐   ┌───────────────────────┐
   │ replica1  (PG 17) │  │ replica2  (PG 17) │   │  logico    (PG 18)    │
   │ nasce VAZIA       │  │ nasce VAZIA       │   │  versão nova, vazio   │
   └───────────────────┘  └───────────────────┘   └───────────────────────┘

   ┌───────────────────┐       ┌────────────────────────────────────────┐
   │ restauracao (17)  │ ◄──── │  /backup  (volume compartilhado)       │
   │ nasce VAZIO       │       │  dumps, backups físicos, arquivo de WAL│
   └───────────────────┘       └────────────────────────────────────────┘
```

* O **`primario`** é o único que já nasce com dados.
* **`replica1`**, **`replica2`** e **`restauracao`** nascem **vazios**: o
  container fica no ar, mas sem PostgreSQL, esperando você colocar dados na
  pasta deles. É você quem transforma cada um em réplica ou em servidor
  restaurado.
* O **`logico`** é um PostgreSQL 18 recém-instalado, com o banco vazio.
* Todos enxergam a pasta **`/backup`**: é o "storage de backup" da empresa.

---

## ✅ Pré-requisitos

* [ ] **Docker** e **Docker Compose v2** (o comando é `docker compose`, com espaço)
* [ ] **`make`** — todos os comandos da trilha começam com ele
* [ ] ~2 GB de RAM livres e ~2 GB de disco para as imagens

> **Você não precisa instalar PostgreSQL nem cliente nenhum.** Tudo roda
> dentro de containers.

Escolha o guia do seu sistema. Cada um instala o Docker, o `make` e o `git`
do zero, passo a passo, e baixa o repositório no lugar certo. Você faz uma
vez só:

| Sistema | Guia | Tempo |
|---|---|---|
| 🪟 Windows 10 ou 11 | **[Preparando o Windows](./docs/windows.md)** (WSL2 + Docker Desktop) | ~20 min |
| 🍎 Mac (Apple Silicon ou Intel) | **[Preparando o Mac](./docs/mac.md)** (Docker Desktop) | ~15 min |
| 🐧 Linux (Ubuntu, Debian, Fedora) | **[Preparando o Linux](./docs/linux.md)** (Docker Engine) | ~10 min |

Ao terminar o guia, volte para cá e continue do passo
[3. Confira o terreno](#3-confira-o-terreno).

### 🪟 Estou no Windows

> ⚠️ No Windows, **todos os comandos da trilha são digitados no terminal do
> Ubuntu (WSL)**, nunca no PowerShell. O [guia](./docs/windows.md) explica
> por quê.

### 🍎🐧 Já tenho o Docker

Se o `docker compose version` (com espaço) já responde com um número de
versão, falta só o `make`, que não vem com o Docker:

| Sistema | Como instalar |
|---|---|
| Ubuntu / Debian | `sudo apt update && sudo apt install make` |
| Fedora | `sudo dnf install make` |
| Mac | `xcode-select --install` |

Se você tem um PostgreSQL instalado na máquina, ele **não atrapalha**: as
portas deste repositório (5460 a 5464) são outras.

---

## ▶️ Começando em 5 minutos

### 1. Baixe o repositório

```bash
git clone https://github.com/sudoers-ai/database_engineer.git
cd database_engineer
```

(Se você seguiu um dos guias de preparação, [Windows](./docs/windows.md),
[Mac](./docs/mac.md) ou [Linux](./docs/linux.md), já fez isso. No Windows,
dentro do terminal do Ubuntu.)

### 2. Confira se você tem o `make`

<!-- rodar: shell -->
```bash
make --version
```

Tem que aparecer a versão, em algo como:

```text
GNU Make 4.3
```

Se aparecer `make: command not found` (ou `comando não encontrado`):

* **no Windows**, você provavelmente está no PowerShell. Abra o terminal do
  **Ubuntu** e veja o [guia de preparação](./docs/windows.md);
* **no Linux ou no Mac**, instale com o comando da tabela
  [logo acima](#-já-tenho-o-docker) e repita este passo.

### 3. Confira o terreno

<!-- rodar: shell -->
```bash
make verificar
```

Ele checa Docker, Compose, portas e memória, e diz em português o que fazer se
algo estiver errado. Saída esperada:

```
Conferindo o ambiente

  ✅ Docker respondendo (29.9.0)
  ✅ Docker Compose v2 (5.6.0)
  ✅ porta 5460 livre (primario)
  ✅ porta 5461 livre (replica1)
  ✅ porta 5462 livre (replica2)
  ✅ porta 5463 livre (restauracao)
  ✅ porta 5464 livre (logico)
  ✅ memória disponível para o Docker: 31 GB

Tudo certo. Próximo passo: make subir
```

> Se alguma porta estiver ocupada, a mensagem diz qual linha do arquivo `.env`
> trocar. Não precisa mexer em mais nada.

### 4. Suba o cluster

<!-- rodar: shell -->
```bash
make subir
```

Na primeira vez ele baixa as imagens do PostgreSQL 17 e 18 (uns 900 MB) e
gera os 18 meses de pedidos. No fim:

```
...
  Tudo no ar. Continue em etapas/01_primario/README.md
```

### 5. Confira que subiu

<!-- rodar: shell -->
```bash
make status
```

```
NÓ           SITUAÇÃO               PAPEL        TL  LSN          LÊ DE      RÉPLICAS PG
primario     no ar                  primário     1   0/705E348    -          0        17
replica1     esperando dados
replica2     esperando dados
restauracao  esperando dados
logico       no ar                  primário     1   0/1BF3750    -          0        18
```

Esse é o retrato do cluster, e você vai olhar para ele o tempo todo. Por
enquanto, só o `primario` e o `logico` têm PostgreSQL rodando. Os outros três
estão **esperando dados**: é assim mesmo. As colunas `TL` (timeline) e `LSN`
(posição no WAL) vão fazer sentido na etapa 1.

---

## 🚪 O que subiu

| Nó | Container | Endereço | Para que serve |
|---|---|---|---|
| `primario` | `dbe_primario` | `localhost:5460` | produção (PG 17) |
| `replica1` | `dbe_replica1` | `localhost:5461` | vira réplica na etapa 5 |
| `replica2` | `dbe_replica2` | `localhost:5462` | vira réplica na etapa 5 |
| `restauracao` | `dbe_restauracao` | `localhost:5463` | recebe os backups (etapas 3 e 4) |
| `logico` | `dbe_logico` | `localhost:5464` | PG 18, recebe a replicação lógica (etapa 8) |

Em todos: banco `liga_sudoers`, usuário `sudoers`, senha `password`.

Você não precisa de cliente instalado. Duas formas de entrar num nó:

```bash
make psql n=primario     # abre o psql (o "prompt do banco")   - saia com \q
make bash n=primario     # abre um terminal DENTRO do servidor - saia com exit
```

Troque `primario` pelo nó que quiser. O `make bash` é o equivalente a entrar
por SSH no servidor: é lá que rodam `pg_dump`, `pg_basebackup` e companhia.

---

## 📖 Como ler os roteiros

Todo bloco de comando dos roteiros diz **onde** ele deve ser colado:

| Aviso antes do bloco | Onde colar |
|---|---|
| 🖥️ **No seu terminal** | no terminal da sua máquina, na pasta do repositório |
| 🐘 **No psql do `replica1`** | dentro do `make psql n=replica1` |
| 📦 **No terminal do `primario`** | dentro do `make bash n=primario` |
| 🔌 **No terminal do `primario` desligado** | dentro do `make bash-desligado n=primario` (etapa 7) |

> **Dica:** deixe três janelas abertas: uma no seu terminal, uma no psql do
> `primario` e uma livre para os outros nós. Errar de janela é o erro número
> 1 desta disciplina — e, num servidor de verdade, o mais perigoso.

---

## 🗺️ A trilha

Cada etapa é uma pasta com o seu próprio README. **Siga na ordem** — cada uma
termina dizendo para onde ir.

| # | Etapa | O que você faz | A prova de que deu certo |
|---|---|---|---|
| 1 | [Conhecer o primário](./etapas/01_primario/README.md) | Explora o servidor, os arquivos e o WAL | Você sabe dizer o RPO e o RTO de hoje |
| 2 | [Backup lógico](./etapas/02_backup_logico/README.md) | `pg_dump` em 3 formatos e restaura uma tabela apagada | `make conferir e=2` |
| 3 | [Backup físico](./etapas/03_backup_fisico/README.md) | `pg_basebackup` e restaura o servidor inteiro em outro nó | `make conferir e=3` |
| 4 | [PITR](./etapas/04_pitr/README.md) | Arquiva o WAL e volta ao segundo antes de um desastre | `make conferir e=4` |
| 5 | [Replicação assíncrona](./etapas/05_replicacao_assincrona/README.md) | Cria duas réplicas com *replication slots* | `make conferir e=5` |
| 6 | [Replicação síncrona](./etapas/06_replicacao_sincrona/README.md) | Garante que nenhuma venda confirmada se perca | `make conferir e=6` |
| 7 | [Failover e switchover](./etapas/07_failover/README.md) | Derruba o primário, promove a réplica e reconstrói o cluster | `make conferir e=7` |
| 8 | [Replicação lógica](./etapas/08_replicacao_logica/README.md) | Replica para o PostgreSQL 18 e ensaia a migração | `make conferir e=8` |
| 9 | [Particionamento](./etapas/09_particionamento/README.md) | Particiona `pedidos` por mês, sem parar a loja | `make conferir e=9` |
| 10 | [Desafios](./desafios/desafios.md) | Júnior, Pleno e Sênior | Os seus entregáveis |

Tempo estimado: 6 a 8 horas, que podem ser divididas em várias aulas. O
ambiente guarda o seu progresso entre uma aula e outra (`make derruba` no
fim da aula, `make subir` no começo da próxima).

> **Faltou numa aula?** As etapas 2, 3, 4, 8 e 9 dependem só do `primario`.
> As etapas 6 e 7 precisam das réplicas da etapa 5: se você não as tem,
> `make gabarito-replicas` cria as duas em segundos.

---

## 📺 Recursos complementares

Os vídeos abaixo, do canal da Sudoers, explicam os fundamentos que esta
disciplina coloca em prática. Assista antes da etapa indicada.

- [Aula 03 - A importância do ACID](https://www.youtube.com/watch?v=3GlHqI0LP9w&list=PLD3-a_5KsN3kBwoeBT78q1ZyARwtwhjwT&index=14) — o "D" de durabilidade é o assunto inteiro deste repositório (antes da etapa 1)  
- [Aula 16 - A importância da Durabilidade](https://www.youtube.com/watch?v=SbPvboEf5lE&list=PLD3-a_5KsN3kBwoeBT78q1ZyARwtwhjwT&index=37) — por que o banco escreve no WAL antes de escrever na tabela (antes da etapa 1)  
- [Aula 17 - Durabilidade: mão na massa](https://www.youtube.com/watch?v=RJDlf1eJiKk&list=PLD3-a_5KsN3kBwoeBT78q1ZyARwtwhjwT&index=38) — o mesmo assunto, no terminal (antes da etapa 4)  
- [Aula 02 - Transacional](https://www.youtube.com/watch?v=e5jm15ui1T0&list=PLD3-a_5KsN3kBwoeBT78q1ZyARwtwhjwT&index=13) — o tipo de banco que você vai operar  
- [Aula 04 - Limitação do Transacional](https://www.youtube.com/watch?v=0jdFniqu-pE&list=PLD3-a_5KsN3kBwoeBT78q1ZyARwtwhjwT&index=15) — por que a tabela que cresce sem parar vira problema (antes da etapa 9)  
- [Curso de SQL Básico](https://www.youtube.com/watch?v=aQd5_vcn18U&list=PLD3-a_5KsN3nuXukrq8kCYtxnZR4FD2nJ) — se o `SELECT`, o `INSERT` e o `UPDATE` ainda não são naturais para você, comece por aqui  

Deixe seu like e comentário nos vídeos do YouTube, isso ajuda e incentiva nosso trabalho.

---

## 📚 Material de apoio

* [🧠 Conceitos: WAL, backup e replicação](./docs/conceitos.md) — o texto que explica o **porquê** de tudo
* [📖 Glossário](./docs/glossario.md) — LSN, timeline, slot, RPO... em português claro
* [✅ Checklist do aluno](./docs/checklist.md) — para marcar o que já fez
* [🪟 Preparando o Windows](./docs/windows.md) — WSL2, Docker Desktop e `make`, passo a passo
* [🍎 Preparando o Mac](./docs/mac.md) — Docker Desktop, `make` e `git`, passo a passo
* [🐧 Preparando o Linux](./docs/linux.md) — Docker Engine, `make` e `git`, passo a passo
* [🔎 Validação por evidências](./docs/validacao_evidencia.md) — como provar que cada etapa funcionou
* [❓ FAQ de aula](./docs/faq.md) — erros comuns e como resolver
* [⌨️ Comandos](./docs/comandos.md) — todo `make` e o `docker` equivalente
* [👩‍💻 Perfis e responsabilidades](./docs/perfis.md) — quem faz o quê num time de dados

---

## 🧰 Comandos do dia a dia

```bash
make ajuda          # lista todos os comandos
make status         # o retrato do cluster: quem é primário, quem é réplica
make psql n=replica1    # entra no banco de um nó
make carga t=30     # simula 30 segundos de vendas no primário
make conferir e=5   # confere se a etapa 5 foi feita
make derruba        # para tudo, MANTENDO os dados (use ao fim da aula)
make subir          # volta de onde parou
make limpar         # para tudo e APAGA os dados (recomeça do zero)
make diagnostico    # relatório completo para mandar ao instrutor
```

---

## 🤝 Contribuição

Contribuições são bem-vindas! Abra uma *issue* ou envie um *pull request*.

Antes de enviar uma mudança nos roteiros, rode as duas conferências de quem
mantém o repositório (precisam de Python 3 na máquina; o aluno não precisa):

```bash
python3 tests/conferir_docs.py                      # links, âncoras e comandos make (sem Docker)
make limpar && python3 tests/seguir_trilha.py       # executa a trilha inteira, como um aluno (~5 min)
```

O `seguir_trilha.py` roda cada bloco marcado com `<!-- rodar: ... -->` nos
READMEs, na ordem. Se um roteiro mandar o aluno fazer algo que não funciona,
ele quebra.

## 📜 Licença

Este projeto está licenciado sob a **Licença SUDOERS**.

---

# ➡️ Comece em [etapas/01_primario/README.md](./etapas/01_primario/README.md)
