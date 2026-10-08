# CONTA-001 — Fundação do módulo Conta

**Base:** Consolidação final v1.3 (seções 3, 4, 5 e 6); Requisitos v1.3; Máquinas de estado v1.3 (C01 e matriz de permissões); Arquitetura e segurança v1.2 (seções 2–6); DDL v1.2; Linha do Tempo v1.2 (6.1).

## Entregue nesta fatia
- Objetos Java de domínio e caso de uso para preparar cadastro de fotógrafo.
- Validações de nome, slug, e-mail, fuso IANA, comprimento de senha e interface de verificação de senha comprometida.
- Cálculo do fim do teste gratuito após 30 dias exatos; decidir política de calendário se exigida em outra revisão.
- Testes unitários sem acesso ao PostgreSQL.

## NÃO entregue (não habilitar endpoint de cadastro)
- Adapter persistente `CadastroPort`: deve ser transacional e gravar `photographers` (`EM_TESTE`), `photographer_users` e `subscriptions` (`TRIAL`) sem usar credencial owner/superuser e sem burlar RLS.
- Integração de `PasswordHasher` com Argon2id / medição de custo.
- Implementação `SenhasComprometidas` e proteção contra abuso/enumeração.
- Bootstrap seguro de identidade, login, sessão JDBC, autorização, CSRF, cookies e invalidação.
- Decisão de como tratar duplicidade de email/slug com resposta pública genérica.
- Testes de integração PostgreSQL, permissões e rollback.

## Invariantes e cautelas
- Nunca editar V1/V2 existentes; migrations futuras são V3+.
- Em `CANCELADA`, acesso restrito depende de BT-001; `podeConsultarCompromissos` NÃO autoriza acesso de fato.
- Fuso inválido falha fechado; dados pessoais não devem ir para logs.
- Evitar endpoint ou `@Service` de cadastro automático sem adapters reais e validação de segurança.

## Próxima fatia CONTA-002
Implementar bootstrap transacional com papéis próprios, autorização limitada, Argon2id, verificação de senhas comprometidas e testes reais de persistência/RLS antes de expor POST /api/contas.
