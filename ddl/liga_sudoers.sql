--
-- PostgreSQL database dump
--

-- Dumped from database version 17.4 (Debian 17.4-1.pgdg120+2)
-- Dumped by pg_dump version 17.4 (Debian 17.4-1.pgdg120+2)

CREATE TABLE public.a (
    a boolean
);


ALTER TABLE public.a OWNER TO sudoers;


CREATE TABLE public.b (
    b boolean
);


ALTER TABLE public.b OWNER TO sudoers;


CREATE TABLE public.datas (
    id integer NOT NULL,
    data date,
    horario time without time zone,
    datahorario timestamp without time zone
);


ALTER TABLE public.datas OWNER TO sudoers;


CREATE SEQUENCE public.datas_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.datas_id_seq OWNER TO sudoers;


ALTER SEQUENCE public.datas_id_seq OWNED BY public.datas.id;


CREATE TABLE public.impares (
    id integer
);

ALTER TABLE public.impares OWNER TO sudoers;


CREATE TABLE public.notas (
    cpf bigint,
    id integer NOT NULL,
    tentativa1 integer,
    tentativa2 integer
);


ALTER TABLE public.notas OWNER TO sudoers;


CREATE SEQUENCE public.notas_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.notas_id_seq OWNER TO sudoers;


ALTER SEQUENCE public.notas_id_seq OWNED BY public.notas.id;



CREATE TABLE public.pares (
    id integer
);


ALTER TABLE public.pares OWNER TO sudoers;


CREATE TABLE public.pessoas (
    cpf bigint NOT NULL,
    nome character varying(100),
    dt_nast date,
    sexo character(1)
);


ALTER TABLE public.pessoas OWNER TO sudoers;


CREATE TABLE public.pessoas2 (
    cpf bigint,
    nome character varying(100),
    sexo character(1)
);


ALTER TABLE public.pessoas2 OWNER TO sudoers;


CREATE TABLE public.salarios (
    cpf bigint NOT NULL,
    depart character varying(20),
    salario numeric(10,2)
);


ALTER TABLE public.salarios OWNER TO sudoers;


ALTER TABLE ONLY public.datas ALTER COLUMN id SET DEFAULT nextval('public.datas_id_seq'::regclass);


ALTER TABLE ONLY public.notas ALTER COLUMN id SET DEFAULT nextval('public.notas_id_seq'::regclass);


COPY public.a (a) FROM stdin;
t
f
\.


COPY public.b (b) FROM stdin;
\.



COPY public.datas (id, data, horario, datahorario) FROM stdin;
1	2016-05-28	16:19:58.59299	2016-05-28 16:16:58.59299
2	2016-05-28	16:21:20.330464	2016-05-28 16:21:20.330464
3	2016-05-27	16:22:46.878812	2016-05-28 16:22:46.878812
\.



COPY public.impares (id) FROM stdin;
0
1
3
5
7
9
\.



COPY public.notas (cpf, id, tentativa1, tentativa2) FROM stdin;
12345678900	1	10	\N
12345678900	2	5	8
12345678900	3	8	10
12345678900	4	\N	9
22345678922	5	10	\N
22345678922	6	10	\N
22345678922	7	9	10
22345678922	8	\N	10
32345678933	9	\N	10
32345678933	10	6	10
32345678933	10	6	5
32345678933	11	6	5
32345678933	12	7	3
32345678933	13	\N	\N
32345678933	14	\N	10
32345678933	15	\N	8
32345678933	16	10	\N
32345678933	17	9	7
\N	18	9	7
\N	19	9	10
\N	20	10	10
\N	21	\N	10
\.


COPY public.pares (id) FROM stdin;
0
2
4
6
8
\.



COPY public.pessoas (cpf, nome, dt_nast, sexo) FROM stdin;
12345678900	Administrador	1985-10-01	M
32345678931	Anne Frank	1929-06-12	F
22345678922	Edgar Allan Poe	1849-10-07	M
3234567893	Edward VII	1894-10-07	M
44345678944	Facebookson de Oliveira	2005-10-23	\N
43445678944	Jadice Denovo	2000-01-13	F
340008999	Rever SonarVida	\N	I
88345678999	Sidney	\N	M
99345678999	Sidney	\N	F
24345678944	Tepergueson Lafora	2000-10-03	M
88345678999	Sidney	\N	M
\.


COPY public.pessoas2 (cpf, nome, sexo) FROM stdin;
\.


COPY public.salarios (cpf, depart, salario) FROM stdin;
12345678900	Central	1001.15
32345678931	RH	800.23
22345678922	Central	1009.06
3234567893	Loja	908.99
44345678944	Loja	909.12
340008999	Loja	909.29
43445678944	RH	802.15
88345678999	Central	1005.36
24345678944	Central	1002.43
\.



SELECT pg_catalog.setval('public.datas_id_seq', 3, true);

SELECT pg_catalog.setval('public.notas_id_seq', 1, false);


ALTER TABLE ONLY public.datas
    ADD CONSTRAINT datas_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.salarios
    ADD CONSTRAINT salarios_pkey PRIMARY KEY (cpf);

