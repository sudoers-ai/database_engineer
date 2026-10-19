# -*- coding: utf-8 -*-
"""
Confere se a documentacao esta coerente com o repositorio.

Ferramenta de quem MANTEM o repositorio. Roda sem banco e sem Docker:

    python3 tests/conferir_docs.py

O que e conferido:
  1. todo link relativo e toda imagem citada nos .md existe no repositorio
     (e toda ancora #secao aponta para um titulo que existe);
  2. todo `make <alvo>` citado nos .md existe no Makefile;
  3. todo `make conferir e=N` citado tem um caso no scripts/conferir.sh;
  4. toda etapa da trilha (etapas/NN_*) esta no tests/seguir_trilha.py.
"""
import os
import re
import sys
import unicodedata
from urllib.parse import unquote

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
V, R, F = "\033[92m", "\033[91m", "\033[0m"
erros = []


def ler(caminho):
    with open(os.path.join(RAIZ, caminho), encoding="utf-8") as fh:
        return fh.read()


def arquivos_md():
    for pasta, subpastas, arquivos in os.walk(RAIZ):
        subpastas[:] = [s for s in subpastas if not s.startswith(".") and s != "entregas"]
        for a in arquivos:
            if a.endswith(".md"):
                yield os.path.relpath(os.path.join(pasta, a), RAIZ)


def ancora(titulo):
    """Mesma regra do GitHub: minusculas, sem pontuacao, espacos viram '-'."""
    t = titulo.strip().lower()
    t = "".join(c for c in t if c.isalnum() or c in " -_" or unicodedata.category(c).startswith("L"))
    return t.replace(" ", "-")


def ancoras_de(md):
    texto = ler(md)
    texto = re.sub(r"```.*?```", "", texto, flags=re.S)
    return {ancora(re.sub(r"[`*]", "", t)) for t in re.findall(r"^#+\s+(.*)$", texto, re.M)}


def conferir_links():
    n = 0
    for md in arquivos_md():
        texto = re.sub(r"```.*?```", "", ler(md), flags=re.S)
        for alvo in re.findall(r"\]\(([^)\s]+)\)", texto):
            if re.match(r"^(https?:|mailto:)", alvo):
                continue
            n += 1
            caminho, _, secao = unquote(alvo).partition("#")
            destino = os.path.normpath(os.path.join(os.path.dirname(md), caminho)) if caminho else md
            if not os.path.exists(os.path.join(RAIZ, destino)):
                erros.append("%s: link quebrado -> %s" % (md, alvo))
            elif secao and destino.endswith(".md") and secao not in ancoras_de(destino):
                erros.append("%s: âncora inexistente -> %s" % (md, alvo))
    return n


def conferir_make():
    alvos = set(re.findall(r"^([a-zA-Z0-9_-]+):", ler("Makefile"), re.M))
    casos = set(re.findall(r"^(\d+)\)", ler("scripts/conferir.sh"), re.M))
    n = 0
    for md in arquivos_md():
        for alvo in re.findall(r"\bmake ([a-z][a-z0-9_-]*)", ler(md)):
            if alvo in ("is", "the", "sure", "git"):  # "apt install make git" etc.
                continue
            n += 1
            if alvo not in alvos:
                erros.append("%s: `make %s` não existe no Makefile" % (md, alvo))
        for e in re.findall(r"make conferir e=(\d+)", ler(md)):
            if e not in casos:
                erros.append("%s: `make conferir e=%s` sem caso no scripts/conferir.sh" % (md, e))
    return n


def conferir_trilha():
    trilha = ler("tests/seguir_trilha.py")
    for etapa in sorted(os.listdir(os.path.join(RAIZ, "etapas"))):
        if "etapas/%s/README.md" % etapa not in trilha:
            erros.append("tests/seguir_trilha.py: falta a etapa %s na TRILHA" % etapa)


def main():
    nl = conferir_links()
    nm = conferir_make()
    conferir_trilha()
    if erros:
        print("%s❌ %d problema(s):%s" % (R, len(erros), F))
        for e in erros:
            print("   " + e)
        return 1
    print("%s✅ documentação coerente: %d links e %d comandos make conferidos.%s" % (V, nl, nm, F))
    return 0


if __name__ == "__main__":
    sys.exit(main())
