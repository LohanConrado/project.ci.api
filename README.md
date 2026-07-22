# 🚀 project.ci.api — API NestJS na AWS (ECR/ECS)

Aplicação **NestJS** conteinerizada, configurada com pipelines automatizados de CI/CD via **GitHub Actions** para realizar testes, *releases* semânticos e *deploy* contínuo na nuvem da **AWS**.

Neste momento, a aplicação foca na conteinerização da API (utilizando seu `Dockerfile`) e no seu deploy no **AWS Elastic Container Service (ECS)**, utilizando o **AWS Elastic Container Registry (ECR)** para armazenar as imagens. Bancos de dados locais via *Docker Compose* não estão sendo provisionados simultaneamente neste escopo.

---

## 📋 Índice

- [Visão Geral da Arquitetura na Nuvem](#visão-geral-da-arquitetura-na-nuvem)
- [Estrutura do Projeto](#estrutura-do-projeto)
- [Executando Localmente](#executando-localmente)
- [Dockerfile da Aplicação (Multi-Stage Build)](#dockerfile-da-aplicação-multi-stage-build)
- [Integração Contínua (CI/CD) e Deploy na AWS](#integração-contínua-cicd-e-deploy-na-aws)
- [Segurança e Dependabot](#segurança-e-dependabot)

---

## Visão Geral da Arquitetura na Nuvem

O pipeline entrega as imagens construídas diretamente na AWS, dispensando a necessidade de orquestração local complexa no momento do *deploy*.

```text
┌─────────────────┐       ┌─────────────────┐       ┌─────────────────┐
│ GitHub Actions  │ ────▶ │    AWS ECR      │ ────▶ │    AWS ECS      │
│ (CI/CD Pipeline)│ Push  │ (Registry de    │ Pull  │ (Container      │
│ Build & Test    │ Image │  Imagens Docker)│ Image │  Orchestration) │
└─────────────────┘       └─────────────────┘       └─────────────────┘
                                                             │
                                                             ▼
                                                    ┌─────────────────┐
                                                    │ API NestJS      │
                                                    │ (Exposta 3000)  │
                                                    └─────────────────┘
```

| Componente      | Tecnologia          | Função                        |
|-----------------|---------------------|-------------------------------|
| API             | NestJS + TypeScript | Lógica de negócio             |
| Container       | Docker              | Empacotamento (`Dockerfile`)  |
| Nuvem (Deploy)  | AWS ECS Express     | Execução / Orquestração       |
| Imagens         | AWS ECR             | Armazenamento seguro de Docker|
| Imagem Base     | `node:26-alpine`    | Runtime leve, focado na API   |

---

## Estrutura do Projeto

Os arquivos principais referentes ao funcionamento e implantação atual:

```text
project-name/
│
├── Dockerfile                          # Build multi-stage da API (NestJS)
├── .github/                            # Configurações do GitHub
│   ├── workflows/ci.yml                # CI/CD (Testes, AWS ECR/ECS, Semantic Release)
│   └── dependabot.yml                  # Atualizações de dependências
├── .env.example                        # Modelo de variáveis de ambiente
├── src/                                # Código-fonte da aplicação NestJS
└── prisma/                             # Schema do banco de dados (Prisma ORM)
```

*(Nota: Arquivos como `docker-compose.yaml` ou configurações de Postgres locais podem existir para ambientes isolados de dev, mas o deploy atual baseia-se estritamente no `Dockerfile` da aplicação).*

---

## Executando Localmente

Para rodar a aplicação localmente sem depender de orquestradores de múltiplos containers, você pode apenas buildar e iniciar a API.

### 1. Configurar Variáveis

```bash
cp .env.example .env
# Edite o .env, informando uma DATABASE_URL válida se necessário.
```

### 2. Rodando via Docker (Recomendado)

Faz o build da imagem isolada da aplicação e a executa:

```bash
# Build da imagem
docker build -t project-ci-api .

# Rodar o container expondo a porta 3000
docker run -p 3000:3000 --env-file .env project-ci-api
```

### 3. Rodando via Node.js (Desenvolvimento)

```bash
npm install
npm run start:dev
```

---

## Dockerfile da Aplicação (Multi-Stage Build)

O arquivo [`Dockerfile`](./Dockerfile) foi arquitetado para produzir uma imagem leve e segura para a AWS, utilizando múltiplos estágios baseados no **Alpine Linux**.

1. **Estágio 1 (Build):** Instala todas as dependências (incluindo `devDependencies`), compila o TypeScript e gera o cliente Prisma. Em seguida, limpa o cache.
2. **Estágio 2 (Runtime):** Copia **apenas** os artefatos compilados (`dist/`) e dependências de produção (`node_modules/` sem *dev*) para uma imagem final enxuta, resultando em inicializações (*cold starts*) muito mais rápidas no AWS ECS e consumindo menos armazenamento no ECR.

---

## Integração Contínua (CI/CD) e Deploy na AWS

O arquivo de pipeline [`ci.yml`](.github/workflows/ci.yml) é o coração da operação. Disparado a cada `push` na branch `main`, ele assegura que a AWS sempre tenha a última versão saudável do código.

1. **Testes Contínuos:** Configura o ambiente Node, instala dependências e executa a suíte de testes (`npm test`).
2. **Semantic Release:** Utiliza o comando `npx semantic-release` nativo para gerar *changelogs*, analisar commits e criar a próxima versão de release sem dependências de ações de terceiros duvidosas.
3. **Autenticação Segura (OIDC):** A action autentica na AWS assumindo roles do IAM de forma segura, sem armazenar as chaves estáticas (`AWS_ACCESS_KEY_ID`) no repositório.
4. **Build & AWS ECR:** A imagem Docker é gerada durante a execução da *Action* e submetida ao Amazon Elastic Container Registry (taggeada com o *hash* do commit e com `latest`).
5. **AWS ECS Express Deploy:** Ao finalizar o envio pro registro, notifica e atualiza o serviço no Amazon Elastic Container Service (ECS) para servir a nova imagem instantaneamente na infraestrutura pré-provisionada.

---

## Segurança e Dependabot

A saúde dos pacotes e configurações é mantida automaticamente pelo **Dependabot** (arquivo `.github/dependabot.yml`). Toda semana, ele escaneia e atualiza (via Pull Requests automáticos):

- **NPM:** Mantém pacotes do Node.js (`package.json`) seguros contra vulnerabilidades recém-descobertas.
- **Docker:** Monitora atualizações da imagem `node` baseada no Alpine, aplicando *patches* do sistema operacional.
- **GitHub Actions:** Atualiza as ações usadas no pipeline (ex: Checkout, AWS logins) e as converte para referências seguras via SHA (*pinning*), protegendo o ciclo de entrega de potenciais *supply chain attacks*.
