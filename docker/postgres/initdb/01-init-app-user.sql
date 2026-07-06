-- ===========================================================
-- Script de inicialização: cria o usuário da aplicação
-- com permissões mínimas necessárias (princípio do menor privilégio).
--
-- Este script é executado automaticamente pelo PostgreSQL
-- na primeira inicialização do container, via
-- /docker-entrypoint-initdb.d/
-- ===========================================================

-- Cria o usuário da aplicação (sem privilégios de superusuário)
CREATE USER app_user WITH PASSWORD 'app_secret';

-- Concede acesso ao banco de dados da aplicação
GRANT CONNECT ON DATABASE project_db TO app_user;

-- Concede permissão de uso no schema public
GRANT USAGE ON SCHEMA public TO app_user;

-- Concede apenas as operações DML necessárias nas tabelas
-- (SELECT, INSERT, UPDATE, DELETE). Sem DROP, CREATE, TRUNCATE etc.
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO app_user;

-- Garante que novas tabelas criadas futuramente (ex: via migrations)
-- também recebam as permissões automaticamente
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO app_user;

-- Concede uso das sequences (necessário para IDs auto-incremento)
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO app_user;

ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT USAGE, SELECT ON SEQUENCES TO app_user;
