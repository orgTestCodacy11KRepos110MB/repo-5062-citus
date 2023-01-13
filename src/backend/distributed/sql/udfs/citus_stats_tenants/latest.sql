CREATE OR REPLACE FUNCTION pg_catalog.citus_stats_tenants (
    OUT colocation_id INT,
    OUT tenant_attribute TEXT,
    OUT read_count INT,
    OUT query_count INT,
    OUT total_query_time DOUBLE PRECISION,
    OUT storage_estimate INT
)
    RETURNS SETOF record
    LANGUAGE plpgsql
    AS $function$
DECLARE
tab_nam TEXT;
dis_col TEXT;
BEGIN
    DROP TABLE IF EXISTS storage;
    CREATE TABLE storage (ten_at TEXT, storage_estimate INT);
    FOR tab_nam, dis_col IN SELECT table_name, distribution_column FROM citus_tables
    LOOP
        EXECUTE 'INSERT INTO storage SELECT ' || dis_col ||', sum(pg_column_size(' || tab_nam || '.*)) FROM ' || tab_nam || ' GROUP BY ' || dis_col;
    END LOOP;
    DROP TABLE IF EXISTS storage_rollup;
    CREATE TABLE storage_rollup (ten_at TEXT, storage_estimate INT);
    INSERT INTO storage_rollup SELECT ten_at, sum(storage.storage_estimate) FROM storage GROUP BY ten_at;
    RETURN QUERY
    SELECT
        tm.colocation_id AS colocation_id,
        storage_rollup.ten_at,
        tm.select_count AS read_count,
        tm.select_count + tm.insert_count AS query_count,
        tm.total_select_time + tm.total_insert_time AS total_query_time,
        storage_rollup.storage_estimate
    FROM tenant_monitor() tm
    FULL OUTER JOIN storage_rollup
    ON tm.tenant_attribute = storage_rollup.ten_at
    ORDER BY tm.colocation_id;
END;
$function$;

CREATE OR REPLACE VIEW citus.citus_stats_tenants AS SELECT * FROM pg_catalog.citus_stats_tenants();

ALTER VIEW citus.citus_stats_tenants SET SCHEMA pg_catalog;
GRANT SELECT ON pg_catalog.citus_stats_tenants TO PUBLIC;
