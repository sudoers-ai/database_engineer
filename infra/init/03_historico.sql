-- ==========================================================================
-- Liga Sudoers - historico de pedidos (18 meses)
--
-- Gera 100.000 pedidos, os itens de cada pedido e a auditoria, espalhados
-- pelos ultimos 540 dias. Roda SOZINHO na primeira vez que o `primario` sobe.
--
-- A semente (setseed) deixa a geracao DETERMINISTICA: em qualquer maquina
-- saem as mesmas pessoas, os mesmos produtos e as mesmas quantidades.
-- So as DATAS mudam, porque sao contadas a partir de hoje: assim sempre
-- existe venda no mes corrente (importante na etapa de particionamento).
-- ==========================================================================

SELECT setseed(0.42);

-- 1) o "esqueleto" de cada pedido: quem comprou, quando e quantos itens
CREATE TEMP TABLE tmp_pedidos AS
SELECT g                                                     AS id,
       1 + floor(random() * 500)::int                        AS id_pessoa,
       date_trunc('second',
         now() - interval '540 days'
               + (g / 100000.0) * interval '539 days'
               + random() * interval '20 hours')             AS dt_venda,
       1 + floor(random() * 4)::int                          AS n_itens
FROM generate_series(1, 100000) AS g;

-- 2) os itens: n_itens produtos sorteados por pedido (sem repetir produto)
CREATE TEMP TABLE tmp_itens AS
SELECT DISTINCT ON (p.id, x.id_produto)
       p.id                         AS id_pedido,
       x.id_produto,
       x.qtde
FROM tmp_pedidos p
CROSS JOIN LATERAL (
    SELECT 1 + floor(random() * 200)::int AS id_produto,
           1 + floor(random() * 3)::int   AS qtde
    FROM generate_series(1, p.n_itens)
) x;

-- 3) grava os pedidos ja com o valor total certo
INSERT INTO public.pedidos (id, id_pessoa, dt_venda, valor_total, created_at, updated_at)
SELECT p.id, p.id_pessoa, p.dt_venda, t.total, p.dt_venda, p.dt_venda
FROM tmp_pedidos p
JOIN (SELECT i.id_pedido, sum(i.qtde * pr.valor_unit) AS total
      FROM tmp_itens i JOIN public.produtos pr ON pr.id = i.id_produto
      GROUP BY i.id_pedido) t ON t.id_pedido = p.id
ORDER BY p.id;

INSERT INTO public.itens_pedidos (id_pedido, id_produto, qtde, valor_total, created_at, updated_at)
SELECT i.id_pedido, i.id_produto, i.qtde, i.qtde * pr.valor_unit, p.dt_venda, p.dt_venda
FROM tmp_itens i
JOIN public.produtos pr ON pr.id = i.id_produto
JOIN tmp_pedidos p ON p.id = i.id_pedido
ORDER BY i.id_pedido, i.id_produto;

-- 4) a auditoria de cada pedido (aparelho, localizacao e telefone)
INSERT INTO public.auditoria_pedidos (id_pedido, dispositivo, geohash, telefone, created_at, updated_at)
SELECT p.id,
       (ARRAY['Android','iPhone','Web Desktop','Web Mobile','iPad'])[1 + floor(random() * 5)::int],
       (ARRAY['6gyf4','6gyc8','7h2wj','75cm8','6gycf','6gkzw'])[1 + floor(random() * 6)::int]
         || substr(md5(p.id::text), 1, 4),
       '(' || (ARRAY['11','21','31','19','13'])[1 + floor(random() * 5)::int] || ') 9'
         || lpad(floor(random() * 100000000)::text, 8, '0'),
       p.dt_venda, p.dt_venda
FROM tmp_pedidos p
ORDER BY p.id;

SELECT setval('public.pedidos_id_seq', (SELECT max(id) FROM public.pedidos));

DROP TABLE tmp_itens;
DROP TABLE tmp_pedidos;

-- estatisticas atualizadas e tabelas sem "lixo" da carga
VACUUM ANALYZE;
