# 🐧 Preparando o Linux

> ⬅️ [README principal](../README.md)

No Linux o Docker roda direto no sistema, sem nada no meio: é o ambiente
mais simples e mais rápido para a trilha. Você prepara uma vez e usa na
disciplina inteira.

Os comandos abaixo são para **Ubuntu** e **Debian** (e derivados, como Linux
Mint e Pop!_OS). No **Fedora**, veja as notas em cada passo.

São quatro passos, cerca de 10 minutos.

| Passo | O que instala | Comando principal |
|---|---|---|
| 1 | Docker Engine e Docker Compose v2 | `curl -fsSL https://get.docker.com \| sh` |
| 2 | Permissão para usar o Docker sem `sudo` | `sudo usermod -aG docker $USER` |
| 3 | `make` e `git` | `sudo apt install make git` |
| 4 | O repositório | `git clone ...` |

> **Já tem Docker?** Confira com `docker compose version` (com espaço). Se
> responder com um número de versão, pule para o passo 3.

---

## Passo 1 — Instalar o Docker

O jeito mais simples é o script oficial da Docker, que detecta a sua
distribuição e instala o Docker Engine **com** o Compose v2:

```bash
curl -fsSL https://get.docker.com -o instalar-docker.sh
sudo sh instalar-docker.sh
```

Ele pede a sua senha (a do `sudo`; ao digitar nada aparece na tela, é
normal) e leva um ou dois minutos.

Confira:

```bash
sudo docker run --rm hello-world
```

Tem que aparecer `Hello from Docker!`.

> **Fedora:** o mesmo script funciona. Depois dele, ligue o serviço:
> `sudo systemctl enable --now docker`.
>
> **Prefere instalar pelo repositório, passo a passo?** O guia oficial está
> em https://docs.docker.com/engine/install/ (escolha a sua distribuição).
>
> ⚠️ **Evite o Docker do Snap** (`snap install docker`, ou a "Ubuntu
> Software"). Ele roda com restrições que causam erros estranhos de
> permissão em pastas. Se você o tem, remova (`sudo snap remove docker`) e
> instale pelo passo acima.

---

## Passo 2 — Usar o Docker sem `sudo`

Por padrão, só o `root` fala com o Docker. A trilha roda centenas de
comandos `docker`; coloque o seu usuário no grupo `docker`:

```bash
sudo usermod -aG docker $USER
```

**Saia da sessão e entre de novo** (ou reinicie o computador): o grupo novo
só vale para sessões novas. Confira, agora **sem** `sudo`:

```bash
docker run --rm hello-world
docker compose version
```

Os dois têm que funcionar. Se aparecer `permission denied while trying to
connect to the Docker daemon`, a sessão ainda é a antiga: saia e entre de
novo.

> O grupo `docker` dá, na prática, poder de administrador da máquina. Num
> computador pessoal de estudo, tudo bem. Num servidor compartilhado, é uma
> decisão de segurança.

---

## Passo 3 — Instalar o `make` e o `git`

```bash
sudo apt update && sudo apt install -y make git
```

(**Fedora:** `sudo dnf install -y make git`.)

Confira:

```bash
make --version
```

```text
GNU Make 4.3
```

---

## Passo 4 — Baixar o repositório

```bash
cd ~
git clone https://github.com/sudoers-ai/database_engineer.git
cd database_engineer
```

Pronto. Volte ao README principal e siga do passo
**[3. Confira o terreno](../README.md#3-confira-o-terreno)** (`make verificar`).

---

## Dicas para o dia a dia no Linux

**Colar no terminal.** Na maioria dos terminais, `Ctrl+Shift+V` (o `Ctrl+V`
sozinho não funciona). Você vai colar muitos blocos de SQL.

**Vários terminais.** Todas as etapas pedem mais de um terminal (um com o
`psql` aberto, outro para os comandos `make`, às vezes um terceiro dentro de
um nó). `Ctrl+Shift+T` abre uma nova aba na maioria dos terminais. Numa
janela nova, entre na pasta:

```bash
cd ~/database_engineer
```

**Conectar um cliente gráfico (DBeaver, pgAdmin...).** Não é necessário para
a trilha, mas funciona: `localhost`, porta `5460` (o `primario`; as réplicas
são `5461` e `5462`), usuário `sudoers`, senha `password`. Se você tem um
PostgreSQL instalado na máquina (porta `5432`), ele não atrapalha.

**Ao fim da aula.** `make derruba` para os containers e mantém o seu
progresso. Na próxima aula: `cd ~/database_engineer` e `make subir`.

---

## 🆘 Problemas comuns no Linux

| O que apareceu | O que é | O que fazer |
|---|---|---|
| `permission denied while trying to connect to the Docker daemon` | Seu usuário não está no grupo `docker`, ou a sessão é anterior ao `usermod` | Passo 2, e saia e entre de novo na sessão |
| `Cannot connect to the Docker daemon` | O serviço do Docker está parado | `sudo systemctl start docker` (e `sudo systemctl enable docker` para ligar sempre) |
| `docker: 'compose' is not a docker command` | Docker sem o Compose v2 (comum no pacote `docker.io` da distribuição) | `sudo apt install docker-compose-v2` (pacote do Ubuntu) ou `sudo apt install docker-compose-plugin` (repositório da Docker) |
| `docker-compose: command not found` | Você digitou com hífen (o Compose v1, antigo) | O comando é `docker compose`, com espaço. Os `make` já usam o certo |
| `make: command not found` | Faltou o passo 3 | `sudo apt install make` |
| `make verificar` diz que uma porta está ocupada | Outro programa usa a porta | Troque a porta no arquivo `.env` (a mensagem diz qual linha) |
| Erros estranhos de permissão em pastas | Docker instalado pelo Snap | Veja o aviso do passo 1 |

Não resolveu? Rode `make diagnostico`, copie a saída e mande ao instrutor.
Veja também o [FAQ geral](./faq.md).
