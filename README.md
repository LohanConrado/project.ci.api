# 🐳 project-name — Ambiente Multi-Container com Docker

Aplicação **NestJS** com banco de dados **PostgreSQL**, orquestrada com **Docker Compose**.  
Este README documenta o processo completo de configuração, execução e testes do ambiente.

---

## 📋 Índice

- [Visão Geral da Arquitetura](#visão-geral-da-arquitetura)
- [Pré-requisitos](#pré-requisitos)
- [Estrutura de Arquivos](#estrutura-de-arquivos)
- [Configuração das Variáveis de Ambiente](#configuração-das-variáveis-de-ambiente)
- [Dockerfile da Aplicação (Multi-Stage Build)](#dockerfile-da-aplicação-multi-stage-build)
- [Dockerfile do PostgreSQL](#dockerfile-do-postgresql)
- [Segurança: Usuário Restrito no Banco de Dados](#segurança-usuário-restrito-no-banco-de-dados)
- [Docker Compose — Serviços, Rede e Volumes](#docker-compose--serviços-rede-e-volumes)
- [Executando os Containers](#executando-os-containers)
- [Testando a Conexão entre os Containers](#testando-a-conexão-entre-os-containers)
- [Comandos Úteis](#comandos-úteis)

---

## Visão Geral da Arquitetura

```
┌─────────────────────────────────────────────────────────┐
│                    project-network (bridge)              │
│                                                         │
│  ┌──────────────────┐       ┌──────────────────────┐   │
│  │  api (NestJS)    │──────▶│  postgres            │   │
│  │  porta: 3000     │       │  porta interna: 5432 │   │
│  │  container:      │       │  container:          │   │
│  │    project       │       │    project-postgres   │   │
│  └──────────────────┘       └──────────┬───────────┘   │
│                                         │               │
└─────────────────────────────────────────┼───────────────┘
                                          │
                                 ┌────────▼────────┐
                                 │  project-volume  │
                                 │  (dados PG)      │
                                 └─────────────────┘
```

| Componente      | Tecnologia          | Versão      |
|-----------------|---------------------|-------------|
| API             | NestJS + TypeScript  | Node 26     |
| ORM             | Prisma               | v7          |
| Banco de dados  | PostgreSQL           | 16 (Alpine) |
| Orquestrador    | Docker Compose       | v2+         |
| Imagem base     | `node:26-alpine3.23` | Alpine      |

---

## Pré-requisitos

Antes de começar, certifique-se de ter instalado:

- [Docker](https://www.docker.com/) `>= 24`
- [Docker Compose](https://docs.docker.com/compose/) `>= 2`

```bash
# Verificar versões instaladas
docker --version
docker compose version
```

---

## Estrutura de Arquivos

```
project-name/
│
├── Dockerfile                          # Build multi-stage da API (NestJS)
├── Dockerfile.postgres                 # Imagem customizada do PostgreSQL
├── docker-compose.yaml                 # Orquestração dos serviços
├── .env                                # Variáveis de ambiente locais (não commitado)
├── .env.example                        # Modelo de variáveis de ambiente
├── .dockerignore                       # Arquivos ignorados pelo Docker build
│
├── docker/
│   └── postgres/
│       └── initdb/
│           └── 01-init-app-user.sql    # Script de criação do usuário restrito
│
├── prisma/
│   └── schema.prisma                   # Schema do banco de dados (Prisma ORM)
│
├── prisma.config.ts                    # Configuração do Prisma CLI
└── src/                                # Código-fonte da aplicação NestJS
```

---

## Configuração das Variáveis de Ambiente

As variáveis de ambiente são usadas para **isolar configurações sensíveis do código-fonte**, seguindo os princípios de [12-factor apps](https://12factor.net/).

### 1. Criar o arquivo `.env` a partir do modelo

```bash
cp .env.example .env
```

### 2. Editar o arquivo `.env` com os valores do ambiente

```dotenv
# ──────────────────────────────────────────
# APLICAÇÃO
# ──────────────────────────────────────────
PORT=3000

# ──────────────────────────────────────────
# BANCO DE DADOS (usuário root — administração)
# ──────────────────────────────────────────
POSTGRES_USER=postgres
POSTGRES_PASSWORD=root_secret
POSTGRES_DB=project_db

# ──────────────────────────────────────────
# BANCO DE DADOS (usuário da aplicação — menor privilégio)
# ──────────────────────────────────────────
APP_DB_USER=app_user
APP_DB_PASSWORD=app_secret

# ──────────────────────────────────────────
# URL DE CONEXÃO (usada pela aplicação e pelo Prisma)
# Formato: postgresql://<user>:<password>@<host>:<port>/<db>
# ──────────────────────────────────────────
DATABASE_URL=postgresql://app_user:app_secret@postgres:5432/project_db?schema=public&connection_limit=30&connect_timeout=30
```

> **⚠️ Atenção:** O arquivo `.env` está listado no `.gitignore` e **não deve ser commitado** no repositório. Nunca exponha senhas, tokens ou chaves de API no controle de versão.

### Como as variáveis são consumidas

| Variável            | Consumido por             | Onde é usado                         |
|---------------------|---------------------------|--------------------------------------|
| `POSTGRES_USER`     | Docker Compose → postgres | Inicialização do container PG        |
| `POSTGRES_PASSWORD` | Docker Compose → postgres | Senha do superusuário do PG          |
| `POSTGRES_DB`       | Docker Compose → postgres | Nome do banco criado automaticamente |
| `APP_DB_USER`       | Docker Compose → postgres | Repassado ao script SQL de init      |
| `APP_DB_PASSWORD`   | Docker Compose → postgres | Senha do usuário da aplicação        |
| `DATABASE_URL`      | Docker Compose → api      | String de conexão do Prisma/NestJS   |

---

## Dockerfile da Aplicação (Multi-Stage Build)

O arquivo [`Dockerfile`](./Dockerfile) utiliza **múltiplos estágios** (`multi-stage build`) para produzir uma imagem final enxuta e segura, baseada na imagem **Alpine**.

```dockerfile
# ──────────────────────────────────────────
# ESTÁGIO 1: build
# Instala dependências, gera o client Prisma e compila o TypeScript
# ──────────────────────────────────────────
FROM node:26-alpine3.23 AS build

WORKDIR /usr/src/app

# Copia apenas os arquivos necessários para instalar dependências
# (aproveitando o cache de camadas do Docker)
COPY package*.json ./
COPY prisma ./prisma

# Instala todas as dependências (incluindo devDependencies para o build)
RUN npm ci

# Copia o restante do código
COPY . .

# Gera o client Prisma, compila o TypeScript e remove devDependencies
RUN npx prisma generate
RUN npm run build
RUN npm prune --omit=dev && npm cache clean --force

# ──────────────────────────────────────────
# ESTÁGIO 2: runtime
# Copia apenas os artefatos necessários do estágio anterior
# Resulta em uma imagem final muito menor
# ──────────────────────────────────────────
FROM node:26-alpine3.23

ENV NODE_ENV=production

WORKDIR /usr/src/app

# Copia apenas o necessário do estágio de build
COPY --from=build /usr/src/app/package*.json ./
COPY --from=build /usr/src/app/prisma.config.ts ./
COPY --from=build /usr/src/app/dist ./dist
COPY --from=build /usr/src/app/node_modules ./node_modules
COPY --from=build /usr/src/app/prisma ./prisma

EXPOSE 3000

# Executa as migrations pendentes antes de iniciar a aplicação
CMD ["sh", "-c", "npx prisma migrate deploy && exec node dist/main.js"]
```

### Por que Multi-Stage + Alpine?

| Benefício                | Descrição                                                                  |
|--------------------------|----------------------------------------------------------------------------|
| **Imagem menor**         | A imagem final não contém compilador TypeScript, devDependencies ou cache  |
| **Segurança**            | Menor superfície de ataque — Alpine tem menos pacotes instalados            |
| **Cache eficiente**      | `COPY package*.json` antes do `COPY . .` maximiza o reuso de camadas      |
| **Sem secrets no build** | Nenhuma senha é passada como argumento de build (`ARG`)                    |

---

## Dockerfile do PostgreSQL

O arquivo [`Dockerfile.postgres`](./Dockerfile.postgres) estende a imagem oficial do PostgreSQL 16 Alpine para incluir o script de inicialização do usuário restrito da aplicação.

```dockerfile
FROM postgres:16-alpine

# Copia o script de inicialização para o diretório especial do PostgreSQL.
# Todos os arquivos .sql e .sh nesse diretório são executados automaticamente
# na primeira inicialização do container (quando o volume ainda está vazio).
COPY docker/postgres/initdb/*.sql /docker-entrypoint-initdb.d/
```

O script copiado é executado **automaticamente e apenas uma vez**, na primeira vez que o container inicializa com um volume vazio.

---

## Segurança: Usuário Restrito no Banco de Dados

Em vez de conectar a aplicação com o usuário `root` (superusuário), um **usuário dedicado com permissões mínimas** é criado via script SQL, seguindo o princípio do **menor privilégio**.

O script [`docker/postgres/initdb/01-init-app-user.sql`](./docker/postgres/initdb/01-init-app-user.sql) é executado automaticamente na primeira inicialização:

```sql
-- Cria o usuário da aplicação (sem privilégios de superusuário)
CREATE USER app_user WITH PASSWORD 'app_secret';

-- Concede acesso ao banco de dados da aplicação
GRANT CONNECT ON DATABASE project_db TO app_user;

-- Concede permissão de uso no schema public
GRANT USAGE ON SCHEMA public TO app_user;

-- Concede apenas as operações DML necessárias (sem DROP, CREATE, TRUNCATE)
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO app_user;

-- Garante que novas tabelas criadas via migrations também recebam permissão
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO app_user;

-- Concede uso das sequences (necessário para IDs auto-incremento)
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO app_user;

ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT USAGE, SELECT ON SEQUENCES TO app_user;
```

### Comparativo de privilégios

| Operação     | `postgres` (root) | `app_user` (aplicação) |
|--------------|:-----------------:|:----------------------:|
| SELECT       | ✅                | ✅                     |
| INSERT       | ✅                | ✅                     |
| UPDATE       | ✅                | ✅                     |
| DELETE       | ✅                | ✅                     |
| CREATE TABLE | ✅                | ❌                     |
| DROP TABLE   | ✅                | ❌                     |
| TRUNCATE     | ✅                | ❌                     |
| GRANT/REVOKE | ✅                | ❌                     |

> A aplicação **nunca usa o usuário root**. A `DATABASE_URL` aponta para `app_user`, que possui apenas as permissões necessárias para o funcionamento da API.

---

## Docker Compose — Serviços, Rede e Volumes

O arquivo [`docker-compose.yaml`](./docker-compose.yaml) define toda a infraestrutura do ambiente multi-container.

```yaml
volumes:
  project-volume:       # Volume nomeado para persistência dos dados do PostgreSQL

networks:
  project-network:      # Rede isolada para comunicação entre containers
    driver: bridge

services:

  # ──────────────────────────────────────────
  # SERVIÇO: banco de dados PostgreSQL
  # ──────────────────────────────────────────
  postgres:
    container_name: project-postgres
    build:
      context: .
      dockerfile: Dockerfile.postgres
    networks:
      - project-network
    restart: always
    environment:
      POSTGRES_USER: postgres          # Superusuário (administração interna)
      POSTGRES_PASSWORD: root_secret
      POSTGRES_DB: project_db
      APP_DB_USER: app_user            # Passado ao script SQL de init
      APP_DB_PASSWORD: app_secret
    volumes:
      - project-volume:/var/lib/postgresql/data   # Persistência dos dados
    ports:
      - '5430:5432'    # 5430 no host → 5432 no container (acesso externo opcional)

  # ──────────────────────────────────────────
  # SERVIÇO: API NestJS
  # ──────────────────────────────────────────
  api:
    container_name: project
    build: .
    networks:
      - project-network
    restart: always
    depends_on:
      - postgres        # Garante que o postgres sobe antes da API
    environment:
      DATABASE_URL: 'postgresql://app_user:app_secret@postgres:5432/project_db?schema=public&connection_limit=30&connect_timeout=30'
    ports:
      - '3000:3000'
```

### Rede Customizada

A rede `project-network` do tipo **bridge** isola a comunicação entre os containers:

- Os containers se comunicam entre si usando o **nome do serviço como hostname** (ex: `postgres` em vez de um IP).
- O banco de dados **não é acessível externamente** pela rede interna — apenas pela porta mapeada `5430` no host (útil para ferramentas como DBeaver ou pgAdmin durante o desenvolvimento).
- Nenhum container da rede `project-network` é acessível por outros containers fora dessa rede.

### Volume Nomeado

O volume `project-volume` garante que os **dados do PostgreSQL persistam** entre reinicializações ou recriações dos containers:

```
project-volume → /var/lib/postgresql/data (dentro do container)
```

> Ao remover o container `project-postgres`, os dados permanecem no volume. Eles só são apagados ao executar `docker compose down -v`.

---

## Executando os Containers

### 1. Configurar as variáveis de ambiente

```bash
cp .env.example .env
# Edite o arquivo .env com os valores desejados
```

### 2. Construir as imagens e subir os containers

```bash
docker compose up --build -d
```

| Flag      | Descrição                                          |
|-----------|----------------------------------------------------|
| `--build` | Reconstrói as imagens (necessário na primeira vez) |
| `-d`      | Sobe os containers em modo detached (background)   |

### 3. Verificar o status dos containers

```bash
docker compose ps
```

Saída esperada:

```
NAME                IMAGE                    STATUS    PORTS
project             project-name-api         Up        0.0.0.0:3000->3000/tcp
project-postgres    project-name-postgres    Up        0.0.0.0:5430->5432/tcp
```

### 4. Acompanhar os logs em tempo real

```bash
# Logs de todos os serviços
docker compose logs -f

# Logs apenas da API
docker compose logs -f api

# Logs apenas do banco de dados
docker compose logs -f postgres
```

### 5. Parar os containers

```bash
# Para e remove os containers (mantém volumes e imagens)
docker compose down

# Para, remove containers E volumes (apaga os dados do banco!)
docker compose down -v
```

---

## Testando a Conexão entre os Containers

### Verificar se a API está respondendo

```bash
curl http://localhost:3000
```

### Verificar se o banco de dados está acessível (via host)

Use um cliente PostgreSQL como `psql`, DBeaver ou pgAdmin com as seguintes configurações:

| Campo   | Valor        |
|---------|--------------|
| Host    | `localhost`  |
| Porta   | `5430`       |
| Banco   | `project_db` |
| Usuário | `app_user`   |
| Senha   | `app_secret` |

Ou via linha de comando:

```bash
# Conectar ao banco usando psql dentro do próprio container (como superusuário)
docker exec -it project-postgres psql -U postgres -d project_db

# Conectar como o usuário da aplicação (para testar as permissões restritas)
docker exec -it project-postgres psql -U app_user -d project_db
```

### Verificar as migrations do Prisma

```bash
# Ver status das migrations aplicadas
docker exec -it project npx prisma migrate status

# Ver logs do container da API (confirmar que migrations rodaram na inicialização)
docker compose logs api | grep -i "prisma"
```

### Testar a comunicação interna entre containers (dentro da rede)

```bash
# Acessar o shell do container da API
docker exec -it project sh

# Dentro do container, pingar o serviço do banco de dados pelo nome do serviço
ping postgres

# Testar a conectividade TCP com a porta do banco de dados
nc -zv postgres 5432
```

---

## Comandos Úteis

```bash
# Reconstruir apenas a imagem da API sem cache
docker compose build --no-cache api

# Inspecionar a rede customizada e ver os containers conectados
docker network inspect project-name_project-network

# Listar todos os volumes Docker
docker volume ls

# Inspecionar o volume de dados do PostgreSQL
docker volume inspect project-name_project-volume

# Ver variáveis de ambiente injetadas em um container
docker exec -it project env

# Executar uma migration manualmente dentro do container da API
docker exec -it project npx prisma migrate deploy

# Abrir o Prisma Studio (interface visual do banco) — somente em desenvolvimento local
DATABASE_URL="postgresql://app_user:app_secret@localhost:5430/project_db" npx prisma studio
```
