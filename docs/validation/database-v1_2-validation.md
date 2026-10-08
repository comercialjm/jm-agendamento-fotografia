# Validação executável do banco — SQL v1.2

Data: 2026-10-07

## Ambiente

- PostgreSQL 18.6
- Docker Compose local
- Banco limpo
- DDL base: JM_Code_Studio_DDL_PostgreSQL_v1_2.sql

SHA-256 da baseline executada:

`3c17b44b543982930143de1a736f341702a0d76db5700f98c9658ed0a97d45e0`

## Resultado estrutural

Validado com sucesso:

- execução integral com `ON_ERROR_STOP=1`;
- transação concluída até `COMMIT`;
- schemas `scheduling` e `authentication`;
- extensão `btree_gist`;
- tabelas de domínio;
- tabelas Spring Session;
- papéis `jm_tenant`, `jm_client`, `jm_admin` e `jm_worker`;
- papéis sem LOGIN, SUPERUSER ou BYPASSRLS;
- RLS habilitado e forçado nas tabelas tenant previstas;
- policies tenant, client e privileged previstas;
- triggers de ocupação;
- exclusion constraint `calendar_no_overlap`.

## Validação comportamental de RLS

Validado:

- sem `app.photographer_id`, tenant não lê registros;
- tenant A lê apenas tenant A;
- tenant B lê apenas tenant B;
- tentativa de escrita cruzada é rejeitada;
- escrita no próprio tenant é permitida;
- `SET LOCAL` não permanece após a transação.

## Validação da agenda

Validado:

- `PENDENTE_APROVACAO` cria `calendar_occupancy`;
- buffer faz parte do intervalo ocupado;
- intervalos adjacentes `[)` são permitidos;
- sobreposição durante o buffer é rejeitada;
- `LIBERADO_PELO_FOTOGRAFO` remove ocupação;
- `REALIZADO` preserva ocupação até `occupied_until`;
- rollback não deixa resíduos;
- duas transações concorrentes não conseguem confirmar ocupações sobrepostas;
- a segunda transação aguarda a primeira e é rejeitada após o COMMIT vencedor.

## DB-VAL-001 — lock do fotógrafo

### Problema

A estratégia aprovada exige bloquear primeiro o fotógrafo com `FOR UPDATE`.

O papel `jm_tenant` possuía `SELECT` em `photographers`, mas não `UPDATE`, e por isso:

`SELECT ... FOR UPDATE`

falhava com:

`permission denied for table photographers`

### Tentativa descartada

Foi testado temporariamente:

`GRANT UPDATE(id) ON scheduling.photographers TO jm_tenant`

O lock passou a funcionar, mas a solução amplia desnecessariamente capacidade de escrita.

O privilégio foi removido.

### Correção adotada

Criada função estreita:

`scheduling.lock_request_photographer()`

Características:

- `SECURITY DEFINER`;
- `search_path` fixado em `scheduling, pg_temp`;
- obtém o fotógrafo exclusivamente de `app.photographer_id`;
- falha sem contexto;
- falha para fotógrafo inexistente;
- executa `FOR UPDATE` na linha correspondente;
- `PUBLIC` sem execução;
- `jm_tenant` recebe apenas `EXECUTE`.

### Testes da correção

Validado:

- sem contexto: falha fechada;
- tenant A: lock da linha A;
- tenant B: lock da linha B;
- UUID inexistente: falha fechada;
- duas sessões concorrentes serializam pelo mesmo fotógrafo;
- `jm_tenant` permanece sem `UPDATE` em `photographers`.

## Pendências

Ainda não validados nesta etapa:

- SQLSTATE `23P01` capturado explicitamente com `\errverbose`;
- comportamento de `jm_client`;
- comportamento de `jm_admin`;
- comportamento de `jm_worker`;
- bootstrap restrito de autenticação/token;
- reutilização real de conexões JDBC;
- integração Flyway;
- integração Hibernate/JPA;
- execução automatizada desses testes.

## Fatos relevantes para a validação:

- PostgreSQL local do projeto passou a usar a porta 55432 por conflito na 5432.
- Spring Boot 4.1.1 requer spring-boot-starter-flyway para auto-configuração.
- Flyway 12.4.0 aplicou V1 e V2 com sucesso em banco vazio.
- V1 gera warning "there is already a transaction in progress" por preservar BEGIN/COMMIT,
  sem impedir a aplicação da migration.
