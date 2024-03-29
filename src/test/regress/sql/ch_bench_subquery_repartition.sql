SET citus.next_shard_id TO 1680000;
CREATE SCHEMA ch_bench_subquery_repartition;
SET search_path = ch_bench_subquery_repartition, public;
SET citus.enable_repartition_joins TO on;

CREATE TABLE order_line (
  ol_w_id int NOT NULL,
  ol_d_id int NOT NULL,
  ol_o_id int NOT NULL,
  ol_number int NOT NULL,
  ol_i_id int NOT NULL,
  ol_delivery_d timestamp NULL DEFAULT NULL,
  ol_amount decimal(6,2) NOT NULL,
  ol_supply_w_id int NOT NULL,
  ol_quantity decimal(2,0) NOT NULL,
  ol_dist_info char(24) NOT NULL,
  PRIMARY KEY (ol_w_id,ol_d_id,ol_o_id,ol_number)
);

CREATE TABLE stock (
  s_w_id int NOT NULL,
  s_i_id int NOT NULL,
  s_quantity decimal(4,0) NOT NULL,
  s_ytd decimal(8,2) NOT NULL,
  s_order_cnt int NOT NULL,
  s_remote_cnt int NOT NULL,
  s_data varchar(50) NOT NULL,
  s_dist_01 char(24) NOT NULL,
  s_dist_02 char(24) NOT NULL,
  s_dist_03 char(24) NOT NULL,
  s_dist_04 char(24) NOT NULL,
  s_dist_05 char(24) NOT NULL,
  s_dist_06 char(24) NOT NULL,
  s_dist_07 char(24) NOT NULL,
  s_dist_08 char(24) NOT NULL,
  s_dist_09 char(24) NOT NULL,
  s_dist_10 char(24) NOT NULL,
  PRIMARY KEY (s_w_id,s_i_id)
);

CREATE TABLE item (
  i_id int NOT NULL,
  i_name varchar(24) NOT NULL,
  i_price decimal(5,2) NOT NULL,
  i_data varchar(50) NOT NULL,
  i_im_id int NOT NULL,
  PRIMARY KEY (i_id)
);

create table nation (
   n_nationkey int not null,
   n_name char(25) not null,
   n_regionkey int not null,
   n_comment char(152) not null,
   PRIMARY KEY ( n_nationkey )
);

create table supplier (
   su_suppkey int not null,
   su_name char(25) not null,
   su_address varchar(40) not null,
   su_nationkey int not null,
   su_phone char(15) not null,
   su_acctbal numeric(12,2) not null,
   su_comment char(101) not null,
   PRIMARY KEY ( su_suppkey )
);

SELECT create_distributed_table('order_line','ol_w_id');
SELECT create_distributed_table('stock','s_w_id');
SELECT create_reference_table('item');
SELECT create_reference_table('nation');
SELECT create_reference_table('supplier');

INSERT INTO order_line SELECT c, c, c, c, c, NULL, c, c, c, 'abc' FROM generate_series(1, 10) as c;
INSERT INTO stock SELECT c, c, c, c, c, c, 'abc', c, c, c, c, c, c, c, c, c, c FROM generate_series(1, 5) as c;
INSERT INTO item SELECT c, 'abc', c, 'abc', c FROM generate_series(1, 3) as c;
INSERT INTO item SELECT 10+c, 'abc', c, 'abc', c FROM generate_series(1, 3) as c;


-- Subquery + repartition is supported when it is an IN query where the subquery
-- returns unique results (because it's converted to an INNER JOIN)
select  s_i_id
    from stock, order_line
    where
        s_i_id in (select i_id from item)
        AND s_i_id = ol_i_id
    order by s_i_id;


-- Subquery + repartition is not supported when it is an IN query where the
-- subquery doesn't return unique results
select  s_i_id
    from stock, order_line
    where
        s_i_id in (select i_im_id from item)
        AND s_i_id = ol_i_id;

-- Subquery + repartition is supported when it is a NOT IN query where the subquery
-- returns unique results
select  s_i_id
    from stock, order_line
    where
        s_i_id not in (select i_id from item)
        AND s_i_id = ol_i_id;

-- Subquery + repartition is not supported when it is a NOT IN where the subquery
-- doesn't return unique results
select  s_i_id
    from stock, order_line
    where
        s_i_id not in (select i_im_id from item)
        AND s_i_id = ol_i_id;

-- Multiple subqueries are supported IN and a NOT IN when no repartition join
-- is necessary and the IN subquery returns unique results
select s_i_id
    from stock
    where
        s_i_id in (select i_id from item)
        AND s_i_id not in (select i_im_id from item);

-- Subquery + repartition is not supported when it contains both an IN and a NOT IN
-- where both subqueries return unique results
select  s_i_id
    from stock, order_line
    where
        s_i_id in (select i_id from item)
        AND s_i_id not in (select i_id from item)
        AND s_i_id = ol_i_id;

-- Subquery + repartition is not supported when it contains both an IN and a NOT IN
-- where the IN subquery returns unique results and the NOT IN returns non unique results
select  s_i_id
    from stock, order_line
    where
        s_i_id in (select i_id from item)
        AND s_i_id not in (select i_im_id from item)
        AND s_i_id = ol_i_id;


-- Subquery + repartition is not supported when it contains both an IN and a NOT IN
-- where the IN subquery returns non unique results and the NOT IN returns unique results
select  s_i_id
    from stock, order_line
    where
        s_i_id in (select i_im_id from item)
        AND s_i_id not in (select i_id from item)
        AND s_i_id = ol_i_id;

-- Subquery + repartition is not supported when it contains both an IN and a NOT IN
-- where both subqueries return non unique results
select  s_i_id
    from stock, order_line
    where
        s_i_id in (select i_im_id from item)
        AND s_i_id not in (select i_im_id from item)
        AND s_i_id = ol_i_id;


-- Actual CHbenCHmark query is supported
select   su_name, su_address
from     supplier, nation
where    su_suppkey in
        (select  mod(s_i_id * s_w_id, 10000)
        from     stock, order_line
        where    s_i_id in
                (select i_id
                 from item
                 where i_data like 'co%')
             and ol_i_id=s_i_id
             and ol_delivery_d > '2010-05-23 12:00:00'
        group by s_i_id, s_w_id, s_quantity
        having   2*s_quantity > sum(ol_quantity))
     and su_nationkey = n_nationkey
     and n_name = 'Germany'
order by su_name;


-- Fallback to public tables with prefilled data
DROP table ch_bench_subquery_repartition.supplier, ch_bench_subquery_repartition.nation;
TRUNCATE order_line, stock, item;
SET search_path = ch_bench_subquery_repartition, public;

insert into stock VALUES
(1, 33, 1000, 1, 1, 1, '', '','','','','','','','','',''),
(1, 44, 1000, 1, 1, 1, '', '','','','','','','','','',''),
(33, 1, 1000, 1, 1, 1, '', '','','','','','','','','',''),
(32, 1, 1000, 1, 1, 1, '', '','','','','','','','','','');


INSERT INTO order_line SELECT c, c, c, c, 33, '2011-01-01', c, c, c, 'abc' FROM generate_series(1, 3) as c;
INSERT INTO order_line SELECT c, c, c, c, 44, '2011-01-01', c, c, c, 'abc' FROM generate_series(4, 6) as c;
INSERT INTO item SELECT c, 'abc', c, 'noco_abc', c FROM generate_series(40, 45) as c;
INSERT INTO item SELECT c, 'abc', c, 'co_abc', c FROM generate_series(30, 33) as c;

-- Actual CHbenCHmark query is supported with data
select   s_name, s_address
from     supplier, nation
where    s_suppkey in
        (select  mod(s_i_id * s_w_id, 10000)
        from     stock, order_line
        where    s_i_id in
                (select i_id
                 from item
                 where i_data like 'co%')
             and ol_i_id=s_i_id
             and ol_delivery_d > '2010-05-23 12:00:00'
        group by s_i_id, s_w_id, s_quantity
        having   2*s_quantity > sum(ol_quantity))
     and s_nationkey = n_nationkey
     and n_name = 'GERMANY'
order by s_name;

-- Confirm that like 'co%' filter filtered out item with id 44
select   s_name, s_address
from     supplier, nation
where    s_suppkey in
        (select  mod(s_i_id * s_w_id, 10000)
        from     stock, order_line
        where    s_i_id in
                (select i_id
                 from item)
             and ol_i_id=s_i_id
             and ol_delivery_d > '2010-05-23 12:00:00'
        group by s_i_id, s_w_id, s_quantity
        having   2*s_quantity > sum(ol_quantity))
     and s_nationkey = n_nationkey
     and n_name = 'GERMANY'
order by s_name;


SET client_min_messages TO WARNING;
DROP SCHEMA ch_bench_subquery_repartition CASCADE;
