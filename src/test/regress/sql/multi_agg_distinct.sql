--
-- MULTI_AGG_DISTINCT
--

SET citus.coordinator_aggregation_strategy TO 'disabled';

-- Create a new range partitioned lineitem table and load data into it
CREATE TABLE lineitem_range (
	l_orderkey bigint not null,
	l_partkey integer not null,
	l_suppkey integer not null,
	l_linenumber integer not null,
	l_quantity decimal(15, 2) not null,
	l_extendedprice decimal(15, 2) not null,
	l_discount decimal(15, 2) not null,
	l_tax decimal(15, 2) not null,
	l_returnflag char(1) not null,
	l_linestatus char(1) not null,
	l_shipdate date not null,
	l_commitdate date not null,
	l_receiptdate date not null,
	l_shipinstruct char(25) not null,
	l_shipmode char(10) not null,
	l_comment varchar(44) not null );
SELECT create_distributed_table('lineitem_range', 'l_orderkey', 'range');

SELECT master_create_empty_shard('lineitem_range') AS new_shard_id
\gset
UPDATE pg_dist_shard SET shardminvalue = 1, shardmaxvalue = 5986
WHERE shardid = :new_shard_id;

SELECT master_create_empty_shard('lineitem_range') AS new_shard_id
\gset
UPDATE pg_dist_shard SET shardminvalue = 8997, shardmaxvalue = 14947
WHERE shardid = :new_shard_id;

\set lineitem_1_data_file :abs_srcdir '/data/lineitem.1.data'
\set lineitem_2_data_file :abs_srcdir '/data/lineitem.2.data'
\set client_side_copy_command '\\copy lineitem_range FROM ' :'lineitem_1_data_file' ' with delimiter '''|''';'
:client_side_copy_command
\set client_side_copy_command '\\copy lineitem_range FROM ' :'lineitem_2_data_file' ' with delimiter '''|''';'
:client_side_copy_command

-- Run aggregate(distinct) on partition column for range partitioned table

SELECT count(distinct l_orderkey) FROM lineitem_range;
SELECT avg(distinct l_orderkey) FROM lineitem_range;

-- Run count(distinct) on join between a range partitioned table and a single
-- sharded table. For this test, we also change a config setting to ensure that
-- we don't repartition any of the tables during the query.


SELECT p_partkey, count(distinct l_orderkey) FROM lineitem_range, part
	WHERE l_partkey = p_partkey
	GROUP BY p_partkey
	ORDER BY p_partkey LIMIT 10;

-- Check that we support more complex expressions.
SELECT count(distinct (l_orderkey)) FROM lineitem_range;
SELECT count(distinct (l_orderkey + 1)) FROM lineitem_range;
SELECT count(distinct (l_orderkey % 5)) FROM lineitem_range;

-- count(distinct) on non-partition column is allowed
SELECT count(distinct l_partkey) FROM lineitem_range;
SELECT count(distinct (l_partkey + 1)) FROM lineitem_range;
SELECT count(distinct (l_partkey % 5)) FROM lineitem_range;

-- Now test append partitioned tables. First run count(distinct) on a single
-- sharded table.
SELECT count(distinct p_mfgr) FROM part;
SELECT p_mfgr, count(distinct p_partkey) FROM part GROUP BY p_mfgr ORDER BY p_mfgr;

-- We support count(distinct) queries on append partitioned tables
-- both on partition column, and non-partition column.
SELECT count(distinct o_orderkey), count(distinct o_custkey) FROM orders;

-- Hash partitioned tables:

CREATE TABLE lineitem_hash (
	l_orderkey bigint not null,
	l_partkey integer not null,
	l_suppkey integer not null,
	l_linenumber integer not null,
	l_quantity decimal(15, 2) not null,
	l_extendedprice decimal(15, 2) not null,
	l_discount decimal(15, 2) not null,
	l_tax decimal(15, 2) not null,
	l_returnflag char(1) not null,
	l_linestatus char(1) not null,
	l_shipdate date not null,
	l_commitdate date not null,
	l_receiptdate date not null,
	l_shipinstruct char(25) not null,
	l_shipmode char(10) not null,
	l_comment varchar(44) not null );
SET citus.shard_replication_factor TO 1;
SELECT create_distributed_table('lineitem_hash', 'l_orderkey', 'hash');

\set client_side_copy_command '\\copy lineitem_hash FROM ' :'lineitem_1_data_file' ' with delimiter '''|''';'
:client_side_copy_command
\set client_side_copy_command '\\copy lineitem_hash FROM ' :'lineitem_2_data_file' ' with delimiter '''|''';'
:client_side_copy_command

-- aggregate(distinct) on partition column is allowed
SELECT count(distinct l_orderkey) FROM lineitem_hash;
SELECT avg(distinct l_orderkey) FROM lineitem_hash;

-- Check that we support more complex expressions.
SELECT count(distinct (l_orderkey)) FROM lineitem_hash;
SELECT count(distinct (l_orderkey + 1)) FROM lineitem_hash;
SELECT count(distinct (l_orderkey % 5)) FROM lineitem_hash;

-- count(distinct) on non-partition column is allowed
SELECT count(distinct l_partkey) FROM lineitem_hash;
SELECT count(distinct (l_partkey + 1)) FROM lineitem_hash;
SELECT count(distinct (l_partkey % 5)) FROM lineitem_hash;


-- agg(distinct) is allowed if we group by partition column
SELECT l_orderkey, count(distinct l_partkey) INTO hash_results FROM lineitem_hash GROUP BY l_orderkey;
SELECT l_orderkey, count(distinct l_partkey) INTO range_results FROM lineitem_range GROUP BY l_orderkey;

-- they should return the same results
SELECT * FROM hash_results h, range_results r WHERE h.l_orderkey = r.l_orderkey AND h.count != r.count;

-- count(distinct) is allowed if we group by non-partition column
SELECT l_partkey, count(distinct l_orderkey) INTO hash_results_np FROM lineitem_hash GROUP BY l_partkey;
SELECT l_partkey, count(distinct l_orderkey) INTO range_results_np FROM lineitem_range GROUP BY l_partkey;

-- they should return the same results
SELECT * FROM hash_results_np h, range_results_np r WHERE h.l_partkey = r.l_partkey AND h.count != r.count;

-- other agg(distinct) are not allowed on non-partition columns even they are grouped
-- on non-partition columns
SELECT SUM(distinct l_partkey) FROM lineitem_hash;
SELECT l_shipmode, sum(distinct l_partkey) FROM lineitem_hash GROUP BY l_shipmode;

DROP TABLE lineitem_hash;
