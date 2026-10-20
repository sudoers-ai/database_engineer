-- ==========================================================================
-- Liga Sudoers - banco TRANSACIONAL (OLTP)
--
-- As 6 tabelas em 3a forma normal que a Liga Sudoers usa ha anos.
--
-- Este arquivo roda SOZINHO na primeira vez que o no `primario` sobe.
-- VOCE NAO EDITA ESTE ARQUIVO. Nesta disciplina voce nao muda o modelo:
-- voce cuida do SERVIDOR (backup, replicacao, particionamento).
-- ==========================================================================

CREATE TABLE public.pessoas (
    id          bigint PRIMARY KEY,
    nome        varchar(255) NOT NULL,
    sexo        varchar(1)   NOT NULL DEFAULT 'M',
    dt_nasc     date         NOT NULL,
    created_at  timestamp DEFAULT now(),
    updated_at  timestamp DEFAULT now()
);

CREATE TABLE public.categorias (
    id          serial PRIMARY KEY,
    descricao   varchar(255) NOT NULL,
    created_at  timestamp DEFAULT now(),
    updated_at  timestamp DEFAULT now()
);

CREATE TABLE public.produtos (
    id            serial PRIMARY KEY,
    id_categoria  integer NOT NULL,
    descricao     varchar(255) NOT NULL,
    valor_unit    numeric(10,2) NOT NULL,
    created_at    timestamp DEFAULT now(),
    updated_at    timestamp DEFAULT now(),
    CONSTRAINT fk_categoria FOREIGN KEY (id_categoria) REFERENCES public.categorias (id)
);

CREATE TABLE public.pedidos (
    id           serial PRIMARY KEY,
    id_pessoa    bigint NOT NULL,
    dt_venda     timestamp NOT NULL,
    valor_total  numeric(10,2) NOT NULL,
    created_at   timestamp DEFAULT now(),
    updated_at   timestamp DEFAULT now(),
    CONSTRAINT fk_pedidos_pessoa FOREIGN KEY (id_pessoa) REFERENCES public.pessoas (id)
);

CREATE TABLE public.itens_pedidos (
    id_pedido    integer NOT NULL,
    id_produto   integer NOT NULL,
    qtde         integer NOT NULL,
    valor_total  numeric(10,2) NOT NULL,
    created_at   timestamp DEFAULT now(),
    updated_at   timestamp DEFAULT now(),
    CONSTRAINT pkey_itens_pedidos PRIMARY KEY (id_pedido, id_produto),
    CONSTRAINT fk_itens_pedido  FOREIGN KEY (id_pedido)  REFERENCES public.pedidos (id),
    CONSTRAINT fk_itens_produto FOREIGN KEY (id_produto) REFERENCES public.produtos (id)
);

CREATE TABLE public.auditoria_pedidos (
    id_pedido    integer PRIMARY KEY,
    dispositivo  varchar(50) NOT NULL,
    geohash      varchar(50) NOT NULL,
    telefone     varchar(20) NOT NULL,
    created_at   timestamp DEFAULT now(),
    updated_at   timestamp DEFAULT now(),
    CONSTRAINT fk_auditoria_pedido FOREIGN KEY (id_pedido) REFERENCES public.pedidos (id)
);

-- --------------------------------------------------------------------------
-- updated_at automatico.
-- Toda vez que uma linha sofre UPDATE, o banco carimba a hora em updated_at.
-- E esse carimbo que permite a um ETL saber "o que mudou desde ontem".
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS trigger AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER set_updated_at_pessoas
    BEFORE UPDATE ON public.pessoas
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER set_updated_at_categorias
    BEFORE UPDATE ON public.categorias
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER set_updated_at_produtos
    BEFORE UPDATE ON public.produtos
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER set_updated_at_pedidos
    BEFORE UPDATE ON public.pedidos
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER set_updated_at_itens_pedidos
    BEFORE UPDATE ON public.itens_pedidos
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER set_updated_at_auditoria_pedidos
    BEFORE UPDATE ON public.auditoria_pedidos
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
