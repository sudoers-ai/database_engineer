# Jornada Engenharia de dados
Bem-vindo ao Mapa do Engenheiro de Dados, um programa prático e desafiador que recria situações reais enfrentadas por profissionais da área de dados. Neste módulo, você será guiado no aprendizado do SQL.

Ao longo do curso, você aprenderá os fundamentos e aplicará técnicas avançadas de SQL, desenvolvendo consultas transacionais e analíticas em SQL, alcançando um nível de maestria.

# Liga Sudoers - Treinamento SQL

Este repositório visa possui uma estrutura para aprendizado do SQL
  * 1 ambiente PostgreSQL 
    
  [Curso SQL](https://www.youtube.com/watch?v=aQd5_vcn18U&list=PLD3-a_5KsN3nuXukrq8kCYtxnZR4FD2nJ)

## Perfil e responsabilidades

Perfis de profissionais e suas responsabilidades no dia a dia dos processos mostrados.  
 - Data Analyst ou Business Intelligence (BI) Analyst

### Data Analyst ou Business Intelligence (BI) Analyst
Criação de Dashboards

    Profissional: Data Analyst ou Business Intelligence (BI) Analyst
        Responsabilidades:
            Criar visualizações e relatórios interativos para tomada de decisão.
            Utilizar ferramentas de BI como Power BI, Tableau, Looker ou Metabase.
            Definir métricas e KPIs com base nos requisitos de negócios.
            Trabalhar diretamente com as partes interessadas para transformar dados em insights acionáveis.

## Pré-requisitos

- Python 3.x
- Docker e Docker Compose


### Instalação do Docker Compose
```bash
sudo apt update
sudo apt install docker-compose-plugin
```

### Verificação da Versão (opcional)
```bash
docker compose version
```

### Parar o PostgreSQL se estiver usando na máquina local (opcional)
```bash
sudo systemctl stop postgresql
```


## Como Executar

### Iniciar Docker pela primeira vez (somente a primeira vez que rodar o processo)
```bash
docker compose up --build
```

### Iniciar Docker pela segunda vez
```bash
docker compose up 
```

### Parar o Docker Compose caso esteja rodando
```bash
docker compose stop
```


## Acessar PostgreSQL
```bash
docker exec -it postgres_liga_sudoers_sql bash 
chown postgres: /var/lib/postgresql/backup/
chmod 0700 /var/lib/postgresql/backup/
```


## Backup - dump Full
```bash
pg_dumpall -c -U sudoers > backup_full.sql
```

## Fazer o Backup FULL e o PITR
```bash
su - postgres
psql -U sudoers -d liga_sudoers
```
Senha: password

```bash
ALTER SYSTEM SET wal_level = 'replica';
ALTER SYSTEM SET archive_mode = 'on';
ALTER SYSTEM SET archive_command = 'cp %p /var/lib/postgresql/backup/%f';
\q

echo "host replication all 0.0.0.0/0 md5" >> /var/lib/postgresql/data/pg_hba.conf
```

```bash
docker restart postgres_liga_sudoers_sql
docker exec -it postgres_liga_sudoers_sql bash 
```

```bash
su - postgres
pg_basebackup -D /var/lib/postgresql/backup/basebackup -Fp -Xs -P -U sudoers 
psql -U sudoers -d liga_sudoers
```
Senha: password



```bash
CREATE TABLE vinicius (id serial);
INSERT into vinicius SELECT generate_series(20, 1000);
SELECT txid_current();
DROP TABLE a;
SELECT txid_current();
INSERT into vinicius SELECT generate_series(2000, 30000);
SELECT txid_current();
DELETE FROM vinicius;
CHECKPOINT;
\q

/usr/lib/postgresql/17/bin/pg_waldump backup/000000010000000000000002 | head

#/usr/lib/postgresql/17/bin/pg_ctl -D /var/lib/postgresql/data stop
```

## Criar a replicação
Abra um segundo terminal (Terminal 2)
```bash
docker exec -it postgres_liga_sudoers_replica bash
su - postgres
chmod 0700 /var/lib/postgresql/data
pg_basebackup -h postgres_liga_sudoers_sql -p 5432 -D /var/lib/postgresql/data/ -U sudoers -Fp -Xs -P -R

/usr/lib/postgresql/17/bin/pg_ctl -D /var/lib/postgresql/data start
```

## Testa Replica
Terminal 01
```bash
psql -U sudoers -d liga_sudoers
SELECT pg_read_file('/etc/hostname');
SELECT pg_is_in_recovery();
SELECT * FROM pg_stat_replication;
```

Terminal 02

```bash
docker exec -it postgres_liga_sudoers_replica bash
psql -U sudoers -d liga_sudoers
SELECT pg_read_file('/etc/hostname');
SELECT pg_is_in_recovery();
SELECT * FROM pg_stat_replication;

```

Desligue o PostgreSQL no Terminal 02
```bash
/usr/lib/postgresql/17/bin/pg_ctl -D /var/lib/postgresql/data stop

```

Insira novos registros no Terminal 01
```bash
insert into vinicius values (7);
insert into vinicius values (8);
insert into vinicius values (9);
SELECT * FROM pg_stat_replication;
```

Ligue o PostgreSQL no Terminal 02 e veja os registros foram enviados para replica
```bash
/usr/lib/postgresql/17/bin/pg_ctl -D /var/lib/postgresql/data start
psql -U sudoers -d liga_sudoers
SELECT * FROM vinicius;
```

Veja os dados no Terminal 01
```bash
SELECT * FROM pg_stat_replication;
```


## Aysnc vs Sync (Alteração no master - terminal 01)
```bash
ALTER SYSTEM SET synchronous_commit = on;
ALTER SYSTEM SET synchronous_standby_names = '*';
SELECT pg_reload_conf();
insert into vinicius values (10);
```

Desligue o PostgreSQL no Terminal 02
```bash
/usr/lib/postgresql/17/bin/pg_ctl -D /var/lib/postgresql/data stop
```

Insira novos registros no Terminal 01
```bash
insert into vinicius values (11);
```

Ligue o PostgreSQL no Terminal 02 e veja os registros foram enviados para replica
```bash
/usr/lib/postgresql/17/bin/pg_ctl -D /var/lib/postgresql/data start
```

## Promovendo a replica (Terminal 2)
```bash
SELECT timeline_id FROM pg_control_checkpoint();
\q

/usr/lib/postgresql/17/bin/pg_ctl promote -D /var/lib/postgresql/data
psql -U sudoers -d liga_sudoers
SELECT timeline_id FROM pg_control_checkpoint();
```

## Contribuição

Contribuições são bem-vindas! Sinta-se à vontade para abrir issues ou enviar pull requests.

## Licença

Este projeto está licenciado sob a Licença SUDOERS.

