-- Create placeholder users and database expected by argo.db stg/afterMigrate callbacks.
-- These are needed because we run migrations with --environment stg (dev env has a
-- hardcoded 0.0.0.0 DB URL that can't be overridden). Real staging has these users
-- provisioned for real; locally we just need them to exist so GRANT doesn't fail.

DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname='argodb_user')  THEN CREATE ROLE argodb_user  LOGIN PASSWORD 'argodb_user'; END IF;
  IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname='auth_user')    THEN CREATE ROLE auth_user    LOGIN PASSWORD 'auth_user';   END IF;
  IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname='crewing_user') THEN CREATE ROLE crewing_user LOGIN PASSWORD 'crewing_user'; END IF;
  IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname='audit_user')   THEN CREATE ROLE audit_user   LOGIN PASSWORD 'audit_user';  END IF;
  IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname='poi_user')     THEN CREATE ROLE poi_user     LOGIN PASSWORD 'poi_user';    END IF;
  IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname='psd_user')     THEN CREATE ROLE psd_user     LOGIN PASSWORD 'psd_user';    END IF;
END
$$;

-- argodb database is referenced by GRANT statements in stg/afterMigrate.sql.
-- Real tables live in the "postgres" database; argodb here is an empty placeholder.
SELECT 'CREATE DATABASE argodb' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'argodb')\gexec

-- Alcyone (surveys/debriefing BE) — uses its own "debriefing" schema.
CREATE SCHEMA IF NOT EXISTS debriefing;
