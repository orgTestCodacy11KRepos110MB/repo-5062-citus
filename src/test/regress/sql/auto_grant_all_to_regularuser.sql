ALTER DEFAULT PRIVILEGES GRANT ALL ON SCHEMAS TO regularuser; -- does not work with citus
ALTER DEFAULT PRIVILEGES GRANT ALL ON TABLES TO regularuser; -- does not work for views with citus
ALTER DEFAULT PRIVILEGES GRANT ALL ON TYPES TO regularuser;
ALTER DEFAULT PRIVILEGES GRANT ALL ON SEQUENCES TO regularuser;
ALTER DEFAULT PRIVILEGES GRANT ALL ON FUNCTIONS TO regularuser;
