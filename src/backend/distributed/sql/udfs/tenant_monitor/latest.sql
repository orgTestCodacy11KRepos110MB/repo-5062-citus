CREATE OR REPLACE FUNCTION tenant_monitor(
    OUT colocation_id INT,
    OUT tenant_attribute TEXT,
    OUT select_count INT,
    OUT total_select_time DOUBLE PRECISION,
    OUT insert_count INT,
    OUT total_insert_time DOUBLE PRECISION)
RETURNS SETOF RECORD
LANGUAGE C
AS 'citus', $$tenant_monitor$$;
