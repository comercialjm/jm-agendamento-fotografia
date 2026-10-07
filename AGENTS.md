AGENTS.md — Agendamento Fotografia / JM Code Studio
Objetivo
Este repositório implementa a versão completa do produto Agendamento Fotografia — JM Code Studio.
A implementação deve permanecer fiel à baseline documental aprovada, com mudanças pequenas,
revisáveis, testáveis e rastreáveis.
Estado desta cópia: preparação inicial. O arquivo
Nenhum código de aplicação deve ser criado ou alterado a partir desta preparação
até que esse documento seja disponibilizado e lido integralmente junto com as demais referências.

Fontes de verdade
Ler integralmente antes de implementar ou revisar uma regra de negócio:
- JM_Code_Studio_Requisitos_Agendamento_Fotografos_v1_3.docx
- JM_Code_Studio_Modelo_Logico_e_DDL_v1_3.docx
- JM_Code_Studio_Maquinas_de_Estado_v1_3.md
- JM_Code_Studio_DDL_PostgreSQL_v1_2.sql
- JM_Code_Studio_Arquitetura_Seguranca_Preparacao_v1_2.md
- JM_Code_Studio_Consolidacao_Final_v1_3.md — pendente de disponibilização
- JM_Code_Studio_Linha_do_Tempo_Desenvolvimento_v1_2.md
- JM_Code_Studio_BT-001_Consulta_Juridica_v1_1.md
  Em caso de conflito entre documentos, não escolher silenciosamente uma interpretação. Registrar:
  documentos/trechos em conflito, impacto técnico, trabalho que pode prosseguir sem a decisão e decisão
  necessária da responsável.
  Decisões técnicas aprovadas
- Backend: Java + Spring Boot + Spring Data JPA + Spring Security.
- Frontend: React + TypeScript + Vite.
- Banco: PostgreSQL.
- Migrações: Flyway com SQL versionado.
- Hibernate: validação do esquema; nunca gerar/atualizar o banco automaticamente.
- Arquitetura: monólito modular por domínio de negócio.
- Worker: processo separado reutilizando a mesma base de código e domínio.
- Repositório: monorepositório GitHub.
- Autenticação do fotógrafo/admin: sessão no servidor.
- Cliente final: sem conta; acesso por link seguro.
- Admin: senha + código temporário enviado por e-mail.
- Isolamento: autorização no backend + RLS no PostgreSQL.
- Estado, ocupação, histórico e outbox pertencem à mesma transação de negócio.
- A ocupação é sincronizada pelo banco; não duplicar no JPA comportamento atribuído a triggers.
- Ordem de locks em mutações de agenda: fotógrafo primeiro; appointment depois, quando aplicável.
- Não colocar credenciais, tokens ou segredos no código, exemplos, fixtures ou logs.
  Versões — baseline técnica proposta após verificação de compatibilidade
  As versões só devem ser gravadas definitivamente no repositório após leitura do documento de
  consolidação ausente e inspeção do repositório real.
- Java: 21 LTS.
- Spring Boot: 4.1.1.
- Maven Wrapper: Maven 3.10.0.
- Node.js: 24 LTS.
- React: 19.3.x.
- Vite: 8.3.x.
- PostgreSQL: 18.6 para o ambiente local/teste, preservando compatibilidade SQL mínima declarada como 15+.
- Flyway: usar a versão gerenciada pelo Spring Boot; não piná-la separadamente sem necessidade.
  Não adotar versões preview, RC, beta ou snapshot.
  Estrutura esperada do monorepositório
  /
  ├─ AGENTS.md
  ├─ README.md
  ├─ docs/
  │  ├─ reference/
  │  ├─ decisions/
  │  └─ validation/
  ├─ backend/
  │  ├─ pom.xml
  │  ├─ mvnw
  │  ├─ mvnw.cmd
  │  ├─ .mvn/wrapper/
  │  └─ src/
  │     ├─ main/java/
  │     ├─ main/resources/
  │     │  └─ db/migration/
  │     └─ test/
  ├─ frontend/
  │  ├─ package.json
  │  ├─ package-lock.json
  │  ├─ src/
  │  └─ tests/
  ├─ infra/
  │  ├─ compose.yaml
  │  └─ postgres/
  └─ scripts/
  A estrutura pode ser ajustada apenas por necessidade concreta encontrada no repositório ou na
  documentação.
  Organização do backend
  Organizar por domínio de negócio, não por camada global. Os módulos aprovados são, no mínimo:
- conta e acesso;
- catálogo de serviços;
- agenda;
- solicitação/agendamento;
- análise pelo fotógrafo;
- acompanhamento e reagendamento;
- compromissos;
- notificações/outbox;
- assinatura e cobrança;
- administração;
- ciclo de vida dos dados.
  Dentro de cada domínio, controllers expõem HTTP, casos de uso coordenam regras/transações/autorização
  e repositories persistem. Entidades JPA não devem virar API pública: usar DTOs.
  Evitar:
- camada service genérica sem responsabilidade clara;
- abstrações criadas “para o futuro”;
- duplicação das regras do banco;
- eventos distribuídos/microserviços sem requisito;
- dependências sem caso de uso concreto.
  Banco, migrations e concorrência
- src/main/resources/db/migration é a fonte executável das migrations.
- O SQL consolidado não deve ser reaplicado como migration única sobre banco já existente.
- Criar migrations incrementais e reproduzíveis.
- spring.jpa.hibernate.ddl-auto=validate.
- RLS, roles/grants, constraints, índices e triggers são parte da funcionalidade e exigem teste real em PostgreSQL.
- Validação de sintaxe não prova concorrência, isolamento ou comportamento de trigger.
- A exclusion constraint de ocupação é uma barreira final; conflitos 23P01 devem ser tratados como conflito de agenda, conforme a baseline.
- O contexto de tenant para RLS deve ser definido pelo servidor por transação e não pode vazar entre conexões reutilizadas.
- Credencial normal da aplicação não pode ser superuser, owner das tabelas nem possuir BYPASSRLS.
- Credencial de migration deve ser separada.
- Não simular PostgreSQL crítico com H2.
  Testes mínimos por alteração
  Sempre que aplicável:
1. teste unitário de regra de domínio;
2. teste de integração com PostgreSQL real para JPA/SQL/transaction/RLS;
3. teste de migration em banco vazio;
4. teste de upgrade das migrations sobre a versão anterior suportada;
5. teste de concorrência para ocupação/aceite/criação quando a alteração tocar agenda;
6. teste de autorização e isolamento entre dois fotógrafos;
7. teste de rollback para garantir ausência de registros parciais/eventos órfãos;
8. teste de idempotência para webhooks/outbox/notificações quando aplicável.
   Não declarar “testado” sem registrar o comando executado e o resultado.
   Segurança
- Sessões server-side; cookies HttpOnly, Secure, SameSite=Lax.
- CSRF ativo nas superfícies autenticadas.
- Argon2id via PasswordEncoder; custo será medido na infraestrutura antes de produção.
- Tokens públicos aleatórios; persistir somente hash quando a baseline assim determinar.
- Nunca registrar senha, código do admin, token de cliente, chave de API ou payload sensível.
- Respostas de autenticação e token devem evitar enumeração.
- Admin não impersona fotógrafo genericamente.
- Ações administrativas privilegiadas exigem autorização explícita, motivo/justificativa quando previsto e auditoria.
- Consultas a dados de cliente pelo suporte devem ser auditadas conforme a baseline.
  Outbox e worker
- Eventos de negócio e outbox são persistidos na mesma transação.
- Notificações externas são enviadas somente após commit.
- Worker deve suportar lease, retomada e deduplicação.
- Não prometer “exactly once” para entrega externa.
- Falha de e-mail/push não desfaz mutação de negócio já confirmada.
- Reprocessamento administrativo precisa ser controlado e auditado.
  Frontend
- React + TypeScript, sem lógica de autorização confiada somente ao cliente.
- Preservar dados de formulário nos conflitos previstos.
- Interface deve refletir os estados e permissões atuais; posse de token não concede ação por si só.
- Não expor IDs/erros internos quando isso revelar existência de conta, cliente ou tenant.
- Priorizar fluxo móvel e acessibilidade básica desde o início.
- Não adicionar biblioteca de estado/global form/design system sem necessidade concreta.
  Configuração
  Segredos entram por variáveis de ambiente ou mecanismo externo apropriado.
  Arquivos versionados podem conter somente exemplos seguros, por exemplo:
  SPRING_DATASOURCE_URL=jdbc:postgresql://localhost:5432/agendamento
  SPRING_DATASOURCE_USERNAME=agendamento_app
  SPRING_DATASOURCE_PASSWORD=change-me-locally
  Nunca reutilizar exemplos em produção.
  Comandos esperados
  Após o bootstrap real do repositório:
# infraestrutura local
docker compose -f infra/compose.yaml up -d

# backend
cd backend
./mvnw clean verify
./mvnw spring-boot:run

# frontend
cd frontend
npm ci
npm run lint
npm run test
npm run build
npm run dev
Adicionar/ajustar comandos neste arquivo quando os scripts reais existirem. Não documentar comando
como funcional antes de executá-lo.
Rastreabilidade
Toda entrega deve registrar, quando aplicável:
- requisito(s) RF;
- regra(s) RN;
- transição(ões) da máquina de estados;
- tabela(s)/constraint(s)/trigger(s);
- endpoint/caso de uso;
- testes que comprovam o comportamento;
- status: documentado, implementado, validado.
  Pendências que não podem ser inventadas
  Entre as pendências já registradas na baseline estão:
- BT-001: retenção, anonimização, exclusão, suspensão prolongada e duração do acesso restrito;
- preço final do plano;
- detalhe verificável das retentativas de cobrança/Asaas e mapeamento financeiro;
- alteração administrativa de registro REALIZADO;
- parâmetros operacionais ainda explicitamente deixados em aberto nos documentos.
  Implementar somente a parte independente dessas decisões.
  Regra para agentes
  Antes de cada alteração:
1. identificar a fonte documental aplicável;
2. verificar se há pendência ou conflito;
3. fazer a menor alteração funcional coerente;
4. executar validações disponíveis;
5. informar exatamente o que mudou, como foi validado e o que continua pendente;
6. atualizar documentação/linha do tempo quando houver avanço real ou decisão aprovada.
   Não reabrir decisões aprovadas sem evidência de conflito técnico/documental.
