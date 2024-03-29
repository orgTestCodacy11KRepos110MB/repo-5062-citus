CREATE SCHEMA generated_identities;
SET search_path TO generated_identities;
SET client_min_messages to ERROR;

SELECT 1 from citus_add_node('localhost', :master_port, groupId=>0);

DROP TABLE IF EXISTS generated_identities_test;

-- create a partitioned table for testing.
CREATE TABLE generated_identities_test (
    a int CONSTRAINT myconname GENERATED BY DEFAULT AS IDENTITY,
    b bigint GENERATED ALWAYS AS IDENTITY (START WITH 10 INCREMENT BY 10),
    c smallint GENERATED BY DEFAULT AS IDENTITY,
    d serial,
    e bigserial,
    f smallserial,
    g int
)
PARTITION BY RANGE (a);
CREATE TABLE generated_identities_test_1_5 PARTITION OF generated_identities_test FOR VALUES FROM (1) TO (5);
CREATE TABLE generated_identities_test_5_50 PARTITION OF generated_identities_test FOR VALUES FROM (5) TO (50);

-- local tables
SELECT citus_add_local_table_to_metadata('generated_identities_test');

\d generated_identities_test

\c - - - :worker_1_port

\d generated_identities.generated_identities_test

\c - - - :master_port
SET search_path TO generated_identities;
SET client_min_messages to ERROR;

SELECT undistribute_table('generated_identities_test');

SELECT citus_remove_node('localhost', :master_port);

SELECT create_distributed_table('generated_identities_test', 'a');

\d generated_identities_test

\c - - - :worker_1_port

\d generated_identities.generated_identities_test

\c - - - :master_port
SET search_path TO generated_identities;
SET client_min_messages to ERROR;

insert into generated_identities_test (g) values (1);

insert into generated_identities_test (g) SELECT 2;

INSERT INTO generated_identities_test (g)
SELECT s FROM generate_series(3,7) s;

SELECT * FROM generated_identities_test ORDER BY 1;

SELECT undistribute_table('generated_identities_test');

SELECT * FROM generated_identities_test ORDER BY 1;

\d generated_identities_test

\c - - - :worker_1_port

\d generated_identities.generated_identities_test

\c - - - :master_port
SET search_path TO generated_identities;
SET client_min_messages to ERROR;

INSERT INTO generated_identities_test (g)
SELECT s FROM generate_series(8,10) s;

SELECT * FROM generated_identities_test ORDER BY 1;

-- distributed table
SELECT create_distributed_table('generated_identities_test', 'a');

-- alter table .. alter column .. add is unsupported
ALTER TABLE generated_identities_test ALTER COLUMN g ADD GENERATED ALWAYS AS IDENTITY;

-- alter table .. alter column is unsupported
ALTER TABLE generated_identities_test ALTER COLUMN b TYPE int;

SELECT alter_distributed_table('generated_identities_test', 'g');

SELECT alter_distributed_table('generated_identities_test', 'b');

SELECT alter_distributed_table('generated_identities_test', 'c');

SELECT undistribute_table('generated_identities_test');

SELECT * FROM generated_identities_test ORDER BY g;

-- reference table

DROP TABLE generated_identities_test;

CREATE TABLE generated_identities_test (
    a int GENERATED BY DEFAULT AS IDENTITY,
    b bigint GENERATED ALWAYS AS IDENTITY (START WITH 10 INCREMENT BY 10),
    c smallint GENERATED BY DEFAULT AS IDENTITY,
    d serial,
    e bigserial,
    f smallserial,
    g int
);

SELECT create_reference_table('generated_identities_test');

\d generated_identities_test

\c - - - :worker_1_port

\d generated_identities.generated_identities_test

\c - - - :master_port
SET search_path TO generated_identities;
SET client_min_messages to ERROR;

INSERT INTO generated_identities_test (g)
SELECT s FROM generate_series(11,20) s;

SELECT * FROM generated_identities_test ORDER BY g;

SELECT undistribute_table('generated_identities_test');

\d generated_identities_test

\c - - - :worker_1_port

\d generated_identities.generated_identities_test

\c - - - :master_port
SET search_path TO generated_identities;
SET client_min_messages to ERROR;

-- alter table .. add column .. GENERATED .. AS IDENTITY
DROP TABLE IF EXISTS color;
CREATE TABLE color (
    color_name VARCHAR NOT NULL
);
SELECT create_distributed_table('color', 'color_name');
ALTER TABLE color ADD COLUMN color_id BIGINT GENERATED ALWAYS AS IDENTITY;
INSERT INTO color(color_name) VALUES ('Red');
ALTER TABLE color ADD COLUMN color_id_1 BIGINT GENERATED ALWAYS AS IDENTITY;
DROP TABLE color;

-- insert data from workers
CREATE TABLE color (
    color_id BIGINT GENERATED ALWAYS AS IDENTITY UNIQUE,
    color_name VARCHAR NOT NULL
);
SELECT create_distributed_table('color', 'color_id');

\c - - - :worker_1_port
SET search_path TO generated_identities;
SET client_min_messages to ERROR;

INSERT INTO color(color_name) VALUES ('Red');

\c - - - :master_port
SET search_path TO generated_identities;
SET client_min_messages to ERROR;

SELECT undistribute_table('color');
SELECT create_distributed_table('color', 'color_id');

\c - - - :worker_1_port
SET search_path TO generated_identities;
SET client_min_messages to ERROR;

INSERT INTO color(color_name) VALUES ('Red');

\c - - - :master_port
SET search_path TO generated_identities;
SET client_min_messages to ERROR;

INSERT INTO color(color_name) VALUES ('Red');

SELECT count(*) from color;

-- modify sequence & alter table
DROP TABLE color;

CREATE TABLE color (
    color_id BIGINT GENERATED ALWAYS AS IDENTITY UNIQUE,
    color_name VARCHAR NOT NULL
);
SELECT create_distributed_table('color', 'color_id');

\c - - - :worker_1_port
SET search_path TO generated_identities;
SET client_min_messages to ERROR;

INSERT INTO color(color_name) VALUES ('Red');

\c - - - :master_port
SET search_path TO generated_identities;
SET client_min_messages to ERROR;

SELECT undistribute_table('color');

ALTER SEQUENCE color_color_id_seq RENAME TO myseq;

SELECT create_distributed_table('color', 'color_id');
\ds+ myseq
\ds+ color_color_id_seq
\d color

\c - - - :worker_1_port
SET search_path TO generated_identities;
SET client_min_messages to ERROR;

\ds+ myseq
\ds+ color_color_id_seq
\d color

INSERT INTO color(color_name) VALUES ('Red');

\c - - - :master_port
SET search_path TO generated_identities;
SET client_min_messages to ERROR;

ALTER SEQUENCE myseq RENAME TO color_color_id_seq;

\ds+ myseq
\ds+ color_color_id_seq

INSERT INTO color(color_name) VALUES ('Red');

\c - - - :worker_1_port
SET search_path TO generated_identities;
SET client_min_messages to ERROR;

\ds+ myseq
\ds+ color_color_id_seq
\d color

INSERT INTO color(color_name) VALUES ('Red');

\c - - - :master_port
SET search_path TO generated_identities;
SET client_min_messages to ERROR;

SELECT alter_distributed_table('co23423lor', shard_count := 6);

INSERT INTO color(color_name) VALUES ('Red');

\c - - - :worker_1_port
SET search_path TO generated_identities;
SET client_min_messages to ERROR;

\ds+ color_color_id_seq

INSERT INTO color(color_name) VALUES ('Red');

\c - - - :master_port
SET search_path TO generated_identities;
SET client_min_messages to ERROR;

DROP SCHEMA generated_identities CASCADE;
