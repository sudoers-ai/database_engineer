-- ==========================================================================
-- Simulador de vendas (roteiro do pgbench, usado por `make carga`)
--
-- Cada execucao deste roteiro e UMA venda: um cliente qualquer compra de 1 a
-- 3 unidades de um produto qualquer. O pedido e o item sao gravados num unico
-- comando (CTE), portanto numa unica transacao: ou entram os dois, ou nenhum.
-- ==========================================================================
\set pessoa  random(1, 500)
\set produto random(1, 200)
\set qtde    random(1, 3)
WITH novo AS (
    INSERT INTO pedidos (id_pessoa, dt_venda, valor_total)
    SELECT :pessoa, now(), valor_unit * :qtde FROM produtos WHERE id = :produto
    RETURNING id, valor_total
)
INSERT INTO itens_pedidos (id_pedido, id_produto, qtde, valor_total)
SELECT id, :produto, :qtde, valor_total FROM novo;
