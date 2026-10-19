# 🍎 Preparando o Mac

> ⬅️ [README principal](../README.md)

No Mac, o Docker roda dentro do **Docker Desktop**, um aplicativo que cuida
de tudo: ele cria uma pequena máquina Linux escondida e é nela que os
containers rodam. Você prepara uma vez e usa na disciplina inteira.

São três passos, cerca de 15 minutos (a maior parte é download).

| Passo | O que instala | Onde |
|---|---|---|
| 1 | Docker Desktop | macOS |
| 2 | `make` e `git` | Terminal |
| 3 | O repositório | Terminal |

> **Onde fica o Terminal:** aperte `Cmd + Espaço`, digite **Terminal** e
> Enter (ou Aplicativos → Utilitários → Terminal). Todos os comandos da
> trilha são digitados nele.

---

## Passo 1 — Instalar o Docker Desktop

**Confira a versão do macOS e o processador.** Menu  (a maçã) → **Sobre
Este Mac**. O Docker Desktop atual pede o **macOS 14 (Sonoma) ou mais novo**:
se o seu for mais antigo, atualize antes (Ajustes do Sistema → Geral →
Atualização de Software). Na mesma janela, veja o processador:

* se aparecer **Chip: Apple M1, M2, M3, M4...**, o seu Mac é *Apple Silicon*;
* se aparecer **Processador: Intel...**, é *Intel*.

1. Abra https://www.docker.com/products/docker-desktop e clique em
   **Download for Mac**, escolhendo a versão do seu processador
   (*Apple Silicon* ou *Intel Chip*).
2. Abra o arquivo `Docker.dmg` baixado e **arraste a baleia para a pasta
   Aplicativos**.
3. Abra o **Docker** pela pasta Aplicativos (ou `Cmd + Espaço` → Docker).
   Na primeira vez:
   * aceite os termos de uso;
   * escolha **Use recommended settings** e digite a senha do Mac, se ele
     pedir;
   * o login na conta Docker é **opcional**: pode pular (*Skip*).
4. Espere a **baleia** aparecer parada na barra de menu, no alto da tela, ao
   lado do relógio. Quando ela para de se mexer, o Docker está pronto.

> **Prefere a linha de comando?** Com o [Homebrew](https://brew.sh)
> instalado, `brew install --cask docker-desktop` faz os itens 1 e 2. Depois, abra o
> Docker uma vez pelos Aplicativos (item 3).

Confira, **no Terminal**:

```bash
docker --version
docker compose version
```

Os dois têm que responder com um número de versão.

> **O Docker Desktop precisa estar aberto** (a baleia na barra de menu)
> sempre que você for trabalhar na disciplina. Se o Terminal responder
> `Cannot connect to the Docker daemon`, é porque ele está fechado.

**Memória.** A trilha precisa de uns 2 GB livres para o Docker. O padrão do
Docker Desktop já é suficiente. Se o `make verificar` reclamar de memória,
aumente em **Settings** (a engrenagem) → **Resources** → **Memory** e
clique em **Apply & restart**.

---

## Passo 2 — Instalar o `make` e o `git`

O Mac não vem com eles, mas a Apple oferece os dois num pacote só, as
*Command Line Tools*:

```bash
xcode-select --install
```

Abre uma janela: clique em **Instalar** e aceite a licença. Leva alguns
minutos. (Se aparecer `command line tools are already installed`, você já
tem tudo: siga em frente.)

Confira:

```bash
make --version
git --version
```

```text
GNU Make 3.81
...
git version 2.39.5 (Apple Git-154)
```

> O Mac vem com o `make` 3.81, uma versão antiga. **Funciona** com este
> repositório: não precisa instalar outro.

---

## Passo 3 — Baixar o repositório

No Terminal:

```bash
cd ~
git clone https://github.com/sudoers-ai/database_engineer.git
cd database_engineer
```

O `cd ~` garante que o repositório fica na sua pasta pessoal
(`/Users/<seu-usuario>/database_engineer`).

> ⚠️ **Evite pastas sincronizadas com a nuvem** (iCloud Drive, a pasta
> *Documentos* ou a *Mesa* quando sincronizadas com o iCloud, Dropbox,
> Google Drive). A sincronização mexe nos arquivos enquanto o Docker os usa,
> e o Docker Desktop pode não ter permissão para enxergá-las.

Pronto. Volte ao README principal e siga do passo
**[3. Confira o terreno](../README.md#3-confira-o-terreno)** (`make verificar`).

---

## Dicas para o dia a dia no Mac

**Colar no Terminal.** `Cmd + V`. Você vai colar muitos blocos de SQL. Se o
Terminal perguntar se quer mesmo colar várias linhas, confirme.

**Vários terminais.** Todas as etapas pedem mais de um terminal (um com o
`psql` aberto, outro para os comandos `make`, às vezes um terceiro dentro de
um nó). No Terminal, `Cmd + T` abre uma **nova aba**, já na mesma pasta. Se
abrir uma janela nova, entre na pasta:

```bash
cd ~/database_engineer
```

**Ver os arquivos do repositório no Finder.** Dentro da pasta do
repositório:

```bash
open .
```

Com o VS Code instalado (e o comando `code` habilitado nele), `code .` abre
o projeto inteiro.

**Conectar um cliente gráfico (DBeaver, pgAdmin, Postico...).** Não é
necessário para a trilha, mas funciona: use `localhost`, porta `5460` (o
`primario`; as réplicas são `5461` e `5462`), usuário `sudoers`, senha
`password`. Se você usa o Postgres.app, ele fica na porta `5432` e não
atrapalha.

**Ao fim da aula.** `make derruba` para os containers e mantém o seu
progresso. Na próxima aula: abra o Docker Desktop, espere a baleia, abra o
Terminal, `cd ~/database_engineer` e `make subir`. (Se quiser economizar
bateria, feche o Docker Desktop depois do `make derruba`: menu da baleia →
**Quit Docker Desktop**.)

---

## 🆘 Problemas comuns no Mac

| O que apareceu | O que é | O que fazer |
|---|---|---|
| `Cannot connect to the Docker daemon` | O Docker Desktop está fechado ou ainda iniciando | Abra o Docker e espere a baleia parar |
| `docker: command not found` | O Docker Desktop nunca foi aberto, ou o Terminal foi aberto antes da instalação | Abra o Docker uma vez pelos Aplicativos, feche o Terminal e abra de novo |
| `make: command not found` ou `xcrun: error: invalid active developer path` | Faltam as *Command Line Tools* (acontece também depois de atualizar o macOS) | Passo 2: `xcode-select --install` |
| O Docker Desktop não instala ("requires a newer macOS") | O Docker Desktop pede o macOS 14 (Sonoma) ou mais novo | Atualize o macOS (menu  → Ajustes do Sistema → Geral → Atualização de Software) |
| Baixou a versão errada (Intel num Apple Silicon, ou o contrário) | O Docker avisa ao abrir, ou fica muito lento | Apague o Docker dos Aplicativos e baixe a versão certa (passo 1) |
| `make verificar` diz que uma porta está ocupada | Outro programa usa a porta | Troque a porta no arquivo `.env` (a mensagem diz qual linha) |
| `make verificar` reclama de memória | O Docker Desktop está com menos de 2 GB | Settings → Resources → Memory, aumente e *Apply & restart* |
| `Operation not permitted` ou arquivos que "somem" | O repositório está numa pasta do iCloud/Dropbox | `pwd`: se o caminho tiver `Mobile Documents`, `iCloud`, `Dropbox` ou `CloudStorage`, clone de novo com `cd ~` (passo 3) |
| O ventilador dispara e a bateria acaba rápido | É o Docker com cinco bancos ligados | Normal durante a aula. No fim, `make derruba` e feche o Docker Desktop |

Não resolveu? Rode `make diagnostico` no Terminal, copie a saída e mande ao
instrutor. Veja também o [FAQ geral](./faq.md).
