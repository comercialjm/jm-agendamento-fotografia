-- JM Code Studio | Modelo lógico e DDL proposto v1.2 | 2026-10-06
-- PostgreSQL 15+; aplicar uma vez em banco vazio com permissão de extensão.
-- Proposta técnica: não implementa integralmente máquinas de estado nem LGPD.
--
-- MUDANÇAS EM RELAÇÃO AO v1.0 (validado em banco de teste em 2026-10-06):
--  (1) Novo estado SUBSTITUIDO_POR_NOVA_SOLICITACAO em appointments e
--      appointment_events. Encerra a proposta cuja sucessora foi criada.
--  (2) Novo CHECK: esse estado exige superseded_at preenchido.
--  (3) sync_appointment_occupancy() passa a PRESERVAR a ocupação quando o
--      registro vai a REALIZADO. O estado do atendimento e a ocupação da
--      agenda são coisas distintas: RN-018 marca a realização no término do
--      serviço, mas RN-004 mantém o intervalo ocupado até o fim do buffer.
--  (4) Comentários sobre a limpeza de ocupações expiradas.
-- Sem alteração: appointments_check6 (justificativa obrigatória em TODA
-- liberação, inclusive quando o motivo não for OTHER) — confirmado por decisão.
BEGIN;
CREATE EXTENSION IF NOT EXISTS btree_gist;
CREATE SCHEMA scheduling;
SET LOCAL search_path = scheduling, public;

-- Fotógrafo e unidade de isolamento da conta
CREATE TABLE photographers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name varchar(150) NOT NULL,
  email varchar(320) NOT NULL,
  email_normalized varchar(320) NOT NULL,
  whatsapp varchar(30),
  whatsapp_normalized varchar(20),
  public_slug varchar(100) NOT NULL UNIQUE,
  timezone varchar(100) NOT NULL,
  account_status text NOT NULL CHECK (account_status IN ('EM_TESTE','ATIVA','SUSPENSA','CANCELADA')),
  booking_horizon_date date,
  pending_reminder_minutes integer CHECK (pending_reminder_minutes > 0),
  public_page_enabled boolean NOT NULL DEFAULT true,
  push_enabled boolean NOT NULL DEFAULT false,
  account_canceled_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- Credencial separada do perfil profissional
CREATE TABLE photographer_users (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  photographer_id uuid NOT NULL REFERENCES photographers(id) UNIQUE,
  email varchar(320) NOT NULL,
  email_normalized varchar(320) NOT NULL UNIQUE,
  password_hash text,
  last_login_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- Identidade administrativa para auditoria
CREATE TABLE admin_users (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email_normalized varchar(320) NOT NULL UNIQUE,
  external_subject text UNIQUE,
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- Catálogo de serviços sem alterar snapshots existentes
CREATE TABLE services (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  photographer_id uuid NOT NULL REFERENCES photographers(id),
  name varchar(150) NOT NULL,
  description text,
  duration_minutes integer NOT NULL CHECK (duration_minutes > 0),
  price_amount numeric(12,2) CHECK (price_amount >= 0),
  price_public boolean NOT NULL DEFAULT false,
  minimum_notice_minutes integer NOT NULL DEFAULT 0 CHECK (minimum_notice_minutes >= 0),
  buffer_after_minutes integer NOT NULL DEFAULT 0 CHECK (buffer_after_minutes >= 0),
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (photographer_id,id)
);

-- Faixas semanais no horário local do fotógrafo
CREATE TABLE weekly_schedule (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  photographer_id uuid NOT NULL REFERENCES photographers(id),
  weekday smallint NOT NULL CHECK (weekday BETWEEN 0 AND 6),
  start_time time NOT NULL,
  end_time time NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK (start_time < end_time), UNIQUE (photographer_id,weekday,start_time,end_time)
);

-- Folgas e bloqueios pontuais
CREATE TABLE calendar_blocks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  photographer_id uuid NOT NULL REFERENCES photographers(id),
  block_type text NOT NULL CHECK (block_type IN ('TIME_OFF','MANUAL_BLOCK')),
  starts_at timestamptz NOT NULL,
  ends_at timestamptz NOT NULL,
  reason text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK (starts_at < ends_at), UNIQUE (photographer_id,id)
);

-- Agregado único de solicitação e agendamento
-- v1.1: SUBSTITUIDO_POR_NOVA_SOLICITACAO encerra a proposta cuja sucessora
-- foi criada pelo cliente. Estado terminal; a rastreabilidade fica em
-- previous_appointment_id da sucessora e em superseded_at deste registro.
CREATE TABLE appointments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  photographer_id uuid NOT NULL REFERENCES photographers(id),
  service_id uuid,
  previous_appointment_id uuid,
  status text NOT NULL CHECK (status IN ('PENDENTE_APROVACAO','CONFIRMADO','RECUSADO','ALTERACAO_PROPOSTA','SUBSTITUIDO_POR_NOVA_SOLICITACAO','CANCELADO_PELO_CLIENTE','LIBERADO_PELO_FOTOGRAFO','LIBERADO_PELO_ADMIN','REALIZADO','ENCERRADO_PELO_SISTEMA')),
  refusal_type text CHECK (refusal_type IN ('NORMAL','SUSPEITA')),
  starts_at timestamptz NOT NULL,
  service_ends_at timestamptz NOT NULL,
  occupied_until timestamptz NOT NULL,
  proposed_starts_at timestamptz,
  client_name varchar(150) NOT NULL,
  client_email varchar(320) NOT NULL,
  client_email_normalized varchar(320) NOT NULL,
  client_whatsapp varchar(30) NOT NULL,
  client_whatsapp_normalized varchar(20) NOT NULL,
  origin_key text NOT NULL,
  location_state varchar(2) NOT NULL,
  location_city varchar(150) NOT NULL,
  location_neighborhood varchar(150) NOT NULL,
  location_name text NOT NULL,
  location_description text NOT NULL,
  service_name_snapshot varchar(150) NOT NULL,
  service_duration_minutes_snap integer NOT NULL CHECK (service_duration_minutes_snap > 0),
  service_buffer_minutes_snap integer NOT NULL CHECK (service_buffer_minutes_snap >= 0),
  service_price_amount_snap numeric(12,2) CHECK (service_price_amount_snap >= 0),
  service_price_public_snap boolean NOT NULL,
  release_reason text CHECK (release_reason IN ('CLIENT_REQUEST','DEPOSIT_UNPAID','PHOTOGRAPHER_UNAVAILABLE','OTHER')),
  release_justification text,
  superseded_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (photographer_id,id),
  FOREIGN KEY (photographer_id,service_id) REFERENCES services(photographer_id,id),
  FOREIGN KEY (photographer_id,previous_appointment_id) REFERENCES appointments(photographer_id,id),
  CHECK (previous_appointment_id IS NULL OR previous_appointment_id <> id),
  CHECK (service_ends_at > starts_at AND occupied_until >= service_ends_at),
  CHECK (extract(epoch FROM (service_ends_at-starts_at)) = service_duration_minutes_snap::bigint * 60),
  CHECK (extract(epoch FROM (occupied_until-service_ends_at)) = service_buffer_minutes_snap::bigint * 60),
  CHECK ((status = 'RECUSADO' AND refusal_type IS NOT NULL) OR (status <> 'RECUSADO' AND refusal_type IS NULL)),
  CHECK (status <> 'ALTERACAO_PROPOSTA' OR proposed_starts_at IS NOT NULL),
  CHECK (status NOT IN ('LIBERADO_PELO_FOTOGRAFO','LIBERADO_PELO_ADMIN') OR (release_reason IS NOT NULL AND length(trim(release_justification)) > 0 AND release_justification IS NOT NULL)),
  -- v1.1: a substituição precisa registrar quando ocorreu
  CHECK (status <> 'SUBSTITUIDO_POR_NOVA_SOLICITACAO' OR superseded_at IS NOT NULL)
);

-- Intervalos operacionais em disputa na mesma agenda.
-- v1.1: a tabela guarda o que bloqueou e o que bloqueia. A disponibilidade
-- sempre filtra por período; linhas com ends_at no passado são inertes e
-- removidas por limpeza periódica (critério: ends_at < now(), NUNCA por status).
CREATE TABLE calendar_occupancy (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  photographer_id uuid NOT NULL REFERENCES photographers(id),
  appointment_id uuid,
  calendar_block_id uuid,
  starts_at timestamptz NOT NULL,
  ends_at timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (starts_at < ends_at),
  CHECK (num_nonnulls(appointment_id,calendar_block_id) = 1),
  FOREIGN KEY (photographer_id,appointment_id) REFERENCES appointments(photographer_id,id),
  FOREIGN KEY (photographer_id,calendar_block_id) REFERENCES calendar_blocks(photographer_id,id),
  UNIQUE (appointment_id), UNIQUE (calendar_block_id),
  CONSTRAINT calendar_no_overlap EXCLUDE USING gist (photographer_id WITH =, tstzrange(starts_at,ends_at,'[)') WITH &&)
);

-- Histórico de negócio append only
CREATE TABLE appointment_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  photographer_id uuid NOT NULL REFERENCES photographers(id),
  appointment_id uuid NOT NULL,
  event_type varchar(50) NOT NULL,
  previous_status text CHECK (previous_status IN ('PENDENTE_APROVACAO','CONFIRMADO','RECUSADO','ALTERACAO_PROPOSTA','SUBSTITUIDO_POR_NOVA_SOLICITACAO','CANCELADO_PELO_CLIENTE','LIBERADO_PELO_FOTOGRAFO','LIBERADO_PELO_ADMIN','REALIZADO','ENCERRADO_PELO_SISTEMA')),
  new_status text CHECK (new_status IN ('PENDENTE_APROVACAO','CONFIRMADO','RECUSADO','ALTERACAO_PROPOSTA','SUBSTITUIDO_POR_NOVA_SOLICITACAO','CANCELADO_PELO_CLIENTE','LIBERADO_PELO_FOTOGRAFO','LIBERADO_PELO_ADMIN','REALIZADO','ENCERRADO_PELO_SISTEMA')),
  actor_type text NOT NULL CHECK (actor_type IN ('CLIENT','PHOTOGRAPHER','ADMIN','SYSTEM')),
  actor_id uuid,
  reason text,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  occurred_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (photographer_id,appointment_id) REFERENCES appointments(photographer_id,id)
);

-- Hashes de credenciais públicas por solicitação
CREATE TABLE appointment_access_tokens (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  photographer_id uuid NOT NULL REFERENCES photographers(id),
  appointment_id uuid NOT NULL,
  token_hash bytea NOT NULL UNIQUE CHECK (octet_length(token_hash) = 32),
  created_at timestamptz NOT NULL DEFAULT now(),
  revoked_at timestamptz,
  FOREIGN KEY (photographer_id,appointment_id) REFERENCES appointments(photographer_id,id)
);

-- Bloqueio local por contato normalizado
CREATE TABLE blocked_contacts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  photographer_id uuid NOT NULL REFERENCES photographers(id),
  contact_type text NOT NULL CHECK (contact_type IN ('EMAIL','WHATSAPP')),
  original_value varchar(320) NOT NULL,
  normalized_value varchar(320) NOT NULL,
  source_appointment_id uuid,
  blocked_at timestamptz NOT NULL DEFAULT now(),
  unblocked_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (photographer_id,source_appointment_id) REFERENCES appointments(photographer_id,id), CHECK (unblocked_at IS NULL OR unblocked_at >= blocked_at)
);

-- Histórico comercial independente de fornecedor
CREATE TABLE subscriptions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  photographer_id uuid NOT NULL REFERENCES photographers(id),
  provider varchar(50),
  provider_customer_id varchar(255),
  provider_subscription_id varchar(255),
  status text NOT NULL CHECK (status IN ('TRIAL','ACTIVE','PAST_DUE','CANCELED','ENDED')),
  trial_started_at timestamptz,
  trial_ends_at timestamptz,
  current_period_started_at timestamptz,
  current_period_ends_at timestamptz,
  cancel_at_period_end boolean NOT NULL DEFAULT false,
  cancellation_requested_at timestamptz,
  canceled_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (photographer_id,id), UNIQUE(provider,provider_subscription_id), CHECK (trial_ends_at IS NULL OR trial_started_at IS NULL OR trial_ends_at > trial_started_at), CHECK (current_period_ends_at IS NULL OR current_period_started_at IS NULL OR current_period_ends_at > current_period_started_at)
);

-- Cobranças da assinatura e não pagamento de ensaios
CREATE TABLE payments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  photographer_id uuid NOT NULL REFERENCES photographers(id),
  subscription_id uuid NOT NULL,
  provider varchar(50) NOT NULL,
  provider_payment_id varchar(255),
  amount numeric(12,2) NOT NULL CHECK (amount >= 0),
  currency char(3) NOT NULL DEFAULT 'BRL',
  status text NOT NULL CHECK (status IN ('PENDING','PAID','FAILED','CANCELED','REFUNDED')),
  due_at timestamptz,
  paid_at timestamptz,
  failed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (photographer_id,subscription_id) REFERENCES subscriptions(photographer_id,id), UNIQUE(provider,provider_payment_id)
);

-- Inbox idempotente do gateway
CREATE TABLE payment_webhook_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  photographer_id uuid REFERENCES photographers(id),
  subscription_id uuid,
  provider varchar(50) NOT NULL,
  provider_event_id varchar(255) NOT NULL,
  event_type varchar(100) NOT NULL,
  payload jsonb NOT NULL,
  received_at timestamptz NOT NULL DEFAULT now(),
  processed_at timestamptz,
  processing_error text,
  attempt_count integer NOT NULL DEFAULT 0 CHECK (attempt_count >= 0),
  UNIQUE(provider,provider_event_id), FOREIGN KEY (photographer_id,subscription_id) REFERENCES subscriptions(photographer_id,id), CHECK (subscription_id IS NULL OR photographer_id IS NOT NULL)
);

-- Intenção durável de processamento externo
CREATE TABLE outbox_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  photographer_id uuid NOT NULL REFERENCES photographers(id),
  aggregate_type varchar(50) NOT NULL,
  aggregate_id uuid,
  event_type varchar(100) NOT NULL,
  payload jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  processed_at timestamptz,
  available_at timestamptz NOT NULL DEFAULT now(),
  locked_until timestamptz,
  attempt_count integer NOT NULL DEFAULT 0 CHECK (attempt_count >= 0),
  last_error text,
  UNIQUE(photographer_id,id)
);

-- Envio lógico deduplicado por evento destinatário e canal
CREATE TABLE notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  photographer_id uuid NOT NULL REFERENCES photographers(id),
  appointment_id uuid,
  outbox_event_id uuid NOT NULL,
  event_type varchar(50) NOT NULL,
  recipient_type text NOT NULL CHECK (recipient_type IN ('CLIENT','PHOTOGRAPHER')),
  recipient text NOT NULL,
  channel text NOT NULL CHECK (channel IN ('EMAIL','PUSH')),
  status text NOT NULL CHECK (status IN ('PENDING','PROCESSING','SENT','FAILED','CANCELED')),
  scheduled_at timestamptz NOT NULL DEFAULT now(),
  sent_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(photographer_id,id), FOREIGN KEY (photographer_id,appointment_id) REFERENCES appointments(photographer_id,id), FOREIGN KEY (photographer_id,outbox_event_id) REFERENCES outbox_events(photographer_id,id), UNIQUE(outbox_event_id,recipient,channel)
);

-- Tentativas de envio e falhas reprocessáveis
CREATE TABLE notification_attempts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  photographer_id uuid NOT NULL REFERENCES photographers(id),
  notification_id uuid NOT NULL,
  attempt_number integer NOT NULL CHECK (attempt_number > 0),
  provider varchar(50),
  provider_id varchar(255),
  status text NOT NULL CHECK (status IN ('SENT','FAILED','UNKNOWN')),
  error_code varchar(100),
  error_message text,
  attempted_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (photographer_id,notification_id) REFERENCES notifications(photographer_id,id), UNIQUE(notification_id,attempt_number)
);

-- Dispositivos PWA do fotógrafo para entrega de push
CREATE TABLE push_subscriptions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  photographer_id uuid NOT NULL REFERENCES photographers(id),
  photographer_user_id uuid NOT NULL REFERENCES photographer_users(id),
  endpoint text NOT NULL UNIQUE,
  p256dh text NOT NULL,
  auth_secret text NOT NULL,
  revoked_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- Registro de operação administrativa autorizada
CREATE TABLE admin_audit_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  admin_user_id uuid NOT NULL REFERENCES admin_users(id),
  photographer_id uuid REFERENCES photographers(id),
  entity_type varchar(50),
  entity_id uuid,
  action varchar(100) NOT NULL,
  reason text NOT NULL CHECK (length(trim(reason)) > 0),
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  occurred_at timestamptz NOT NULL DEFAULT now()
);

-- Parâmetros antiabuso alteráveis sem mudança de código
CREATE TABLE platform_settings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  setting_key text NOT NULL UNIQUE,
  integer_value integer NOT NULL CHECK (integer_value > 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE photographer_users ADD CONSTRAINT user_tenant_key UNIQUE(photographer_id,id);
ALTER TABLE push_subscriptions ADD CONSTRAINT push_user_tenant_fk FOREIGN KEY(photographer_id,photographer_user_id) REFERENCES photographer_users(photographer_id,id);
CREATE INDEX services_active_idx ON services(photographer_id,active);
CREATE INDEX appointments_status_idx ON appointments(photographer_id,status);
CREATE INDEX appointments_start_idx ON appointments(photographer_id,starts_at);
CREATE INDEX appointments_email_pending_idx ON appointments(photographer_id,client_email_normalized) WHERE status='PENDENTE_APROVACAO';
CREATE INDEX appointments_phone_pending_idx ON appointments(photographer_id,client_whatsapp_normalized) WHERE status='PENDENTE_APROVACAO';
CREATE INDEX appointments_origin_pending_idx ON appointments(photographer_id,origin_key) WHERE status='PENDENTE_APROVACAO';
CREATE INDEX appointments_previous_idx ON appointments(photographer_id,previous_appointment_id);
CREATE INDEX appointments_completion_idx ON appointments(service_ends_at) WHERE status='CONFIRMADO';
CREATE INDEX blocks_start_idx ON calendar_blocks(photographer_id,starts_at,ends_at);
-- v1.1: apoia a limpeza periódica de ocupações expiradas
CREATE INDEX occupancy_expired_idx ON calendar_occupancy(ends_at);
CREATE UNIQUE INDEX blocked_contact_active_key ON blocked_contacts(photographer_id,contact_type,normalized_value) WHERE unblocked_at IS NULL;
CREATE INDEX events_history_idx ON appointment_events(photographer_id,appointment_id,occurred_at,id);
CREATE INDEX notifications_pending_idx ON notifications(status,scheduled_at) WHERE status IN ('PENDING','FAILED');
CREATE INDEX outbox_pending_idx ON outbox_events(available_at,created_at) WHERE processed_at IS NULL;
CREATE INDEX webhook_pending_idx ON payment_webhook_events(received_at) WHERE processed_at IS NULL;
CREATE INDEX audit_tenant_time_idx ON admin_audit_log(photographer_id,occurred_at);
INSERT INTO platform_settings(setting_key,integer_value) VALUES
 ('pending_per_email',2),('pending_per_whatsapp',2),('pending_per_origin',3),('attempts_per_origin',5),('attempt_window_seconds',600);

-- Os escritores de domínio devem bloquear photographers com FOR UPDATE antes
-- de validar e alterar agenda/conta/contatos. Ocupação é derivada por triggers.
--
-- v1.1: REALIZADO entra na lista de estados que OCUPAM a agenda. O intervalo
-- gravado continua sendo [starts_at, occupied_until), então o buffer segue
-- protegido mesmo depois que o atendimento é marcado como realizado.
-- Como ends_at já expirou nesse caso, a linha é inerte para horários futuros
-- e pode ser removida por limpeza periódica baseada em ends_at < now().
CREATE FUNCTION sync_appointment_occupancy() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.status IN ('PENDENTE_APROVACAO','CONFIRMADO','REALIZADO') THEN
    INSERT INTO scheduling.calendar_occupancy(photographer_id,appointment_id,starts_at,ends_at)
    VALUES(NEW.photographer_id,NEW.id,NEW.starts_at,NEW.occupied_until)
    ON CONFLICT(appointment_id) DO UPDATE SET starts_at=EXCLUDED.starts_at,ends_at=EXCLUDED.ends_at;
  ELSE
    DELETE FROM scheduling.calendar_occupancy WHERE appointment_id=NEW.id;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER appointment_occupancy_sync AFTER INSERT OR UPDATE OF status,starts_at,occupied_until ON appointments FOR EACH ROW EXECUTE FUNCTION sync_appointment_occupancy();
CREATE FUNCTION sync_block_occupancy() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP='DELETE' THEN
    DELETE FROM scheduling.calendar_occupancy WHERE calendar_block_id=OLD.id;
    RETURN OLD;
  END IF;
  INSERT INTO scheduling.calendar_occupancy(photographer_id,calendar_block_id,starts_at,ends_at)
  VALUES(NEW.photographer_id,NEW.id,NEW.starts_at,NEW.ends_at)
  ON CONFLICT(calendar_block_id) DO UPDATE SET starts_at=EXCLUDED.starts_at,ends_at=EXCLUDED.ends_at;
  RETURN NEW;
END $$;
CREATE TRIGGER block_occupancy_sync AFTER INSERT OR UPDATE OF starts_at,ends_at ON calendar_blocks FOR EACH ROW EXECUTE FUNCTION sync_block_occupancy();
CREATE TRIGGER block_occupancy_delete BEFORE DELETE ON calendar_blocks FOR EACH ROW EXECUTE FUNCTION sync_block_occupancy();
CREATE FUNCTION maintain_updated_at() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at=clock_timestamp(); RETURN NEW; END $$;
CREATE TRIGGER photographers_updated BEFORE UPDATE ON photographers FOR EACH ROW EXECUTE FUNCTION maintain_updated_at();
CREATE TRIGGER photographer_users_updated BEFORE UPDATE ON photographer_users FOR EACH ROW EXECUTE FUNCTION maintain_updated_at();
CREATE TRIGGER admin_users_updated BEFORE UPDATE ON admin_users FOR EACH ROW EXECUTE FUNCTION maintain_updated_at();
CREATE TRIGGER services_updated BEFORE UPDATE ON services FOR EACH ROW EXECUTE FUNCTION maintain_updated_at();
CREATE TRIGGER weekly_schedule_updated BEFORE UPDATE ON weekly_schedule FOR EACH ROW EXECUTE FUNCTION maintain_updated_at();
CREATE TRIGGER calendar_blocks_updated BEFORE UPDATE ON calendar_blocks FOR EACH ROW EXECUTE FUNCTION maintain_updated_at();
CREATE TRIGGER appointments_updated BEFORE UPDATE ON appointments FOR EACH ROW EXECUTE FUNCTION maintain_updated_at();
CREATE TRIGGER subscriptions_updated BEFORE UPDATE ON subscriptions FOR EACH ROW EXECUTE FUNCTION maintain_updated_at();
CREATE TRIGGER payments_updated BEFORE UPDATE ON payments FOR EACH ROW EXECUTE FUNCTION maintain_updated_at();
CREATE TRIGGER push_subscriptions_updated BEFORE UPDATE ON push_subscriptions FOR EACH ROW EXECUTE FUNCTION maintain_updated_at();
CREATE TRIGGER platform_settings_updated BEFORE UPDATE ON platform_settings FOR EACH ROW EXECUTE FUNCTION maintain_updated_at();

CREATE FUNCTION protect_appointment_history() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF NEW.photographer_id IS DISTINCT FROM OLD.photographer_id OR
    ROW(NEW.service_name_snapshot,NEW.service_duration_minutes_snap,NEW.service_buffer_minutes_snap,NEW.service_price_amount_snap,NEW.service_price_public_snap)
    IS DISTINCT FROM ROW(OLD.service_name_snapshot,OLD.service_duration_minutes_snap,OLD.service_buffer_minutes_snap,OLD.service_price_amount_snap,OLD.service_price_public_snap)
 THEN RAISE EXCEPTION 'tenant e snapshot do agendamento são imutáveis'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER appointment_history_guard BEFORE UPDATE ON appointments FOR EACH ROW EXECUTE FUNCTION protect_appointment_history();

-- Não conceder DML direto em calendar_occupancy ao papel da aplicação.
-- Não conceder UPDATE/DELETE em appointment_events/admin_audit_log ao papel comum.
-- Roles, RLS e política de exclusão: configurar após decisões de segurança/BT-001.
-- A limpeza de calendar_occupancy expirada deve usar ends_at < now(), nunca status.

-- Revisão v1.2: estrutura aprovada; ainda não executada nesta entrega.
-- Script completo para BANCO VAZIO, não migration de banco existente.
ALTER TABLE photographers
 ADD suspended_at timestamptz,
 ADD suspension_reason text,
 ADD security_blocked_at timestamptz,
 ADD security_block_reason text,
 ADD security_blocked_by uuid REFERENCES admin_users(id),
 ADD CONSTRAINT suspension_details CHECK(account_status <> 'SUSPENSA' OR
   (suspended_at IS NOT NULL AND suspension_reason IS NOT NULL AND length(trim(suspension_reason))>0)),
 ADD CONSTRAINT security_block_details CHECK
   ((security_blocked_at IS NULL AND security_block_reason IS NULL AND security_blocked_by IS NULL) OR
    (security_blocked_at IS NOT NULL AND security_block_reason IS NOT NULL AND length(trim(security_block_reason))>0 AND security_blocked_by IS NOT NULL));
ALTER TABLE photographers ALTER COLUMN pending_reminder_minutes SET DEFAULT 1440;
ALTER TABLE admin_users ADD password_hash text;
ALTER TABLE outbox_events ADD lock_owner uuid;
ALTER TABLE notifications ADD lock_owner uuid, ADD locked_until timestamptz,
 ADD attempt_count integer NOT NULL DEFAULT 0 CHECK(attempt_count>=0),
 ADD last_error text, ADD expires_at timestamptz;
-- SENT significa aceitação pelo provedor. Entrega é registrada separadamente.
ALTER TABLE notifications ADD delivered_at timestamptz;
CREATE INDEX notifications_claim_idx ON notifications(scheduled_at,locked_until)
 WHERE status IN ('PENDING','PROCESSING');
CREATE INDEX appointments_reminder_idx ON appointments(photographer_id,created_at)
 WHERE status='PENDENTE_APROVACAO';

-- Lembrete único; criação e vínculo em transação com deduplicação.
CREATE TABLE appointment_reminders (
 appointment_id uuid PRIMARY KEY,
 photographer_id uuid NOT NULL,
 due_at timestamptz NOT NULL,
 outbox_event_id uuid,
 sent_at timestamptz,
 FOREIGN KEY(photographer_id,appointment_id) REFERENCES appointments(photographer_id,id),
 FOREIGN KEY(photographer_id,outbox_event_id) REFERENCES outbox_events(photographer_id,id)
);

-- Credenciais temporárias não pertencem à outbox de negócio.
CREATE TABLE password_reset_tokens (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 photographer_user_id uuid REFERENCES photographer_users(id),
 admin_user_id uuid REFERENCES admin_users(id),
 token_hash bytea NOT NULL UNIQUE CHECK(octet_length(token_hash)=32),
 created_at timestamptz NOT NULL DEFAULT now(),
 expires_at timestamptz NOT NULL,
 consumed_at timestamptz,
 revoked_at timestamptz,
 CHECK(num_nonnulls(photographer_user_id,admin_user_id)=1),
 CHECK(expires_at>created_at)
);
CREATE TABLE admin_login_challenges (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 admin_user_id uuid NOT NULL REFERENCES admin_users(id),
 login_binding_hash bytea NOT NULL CHECK(octet_length(login_binding_hash)=32),
 code_mac bytea NOT NULL CHECK(octet_length(code_mac)=32),
 created_at timestamptz NOT NULL DEFAULT now(),
 expires_at timestamptz NOT NULL,
 attempt_count integer NOT NULL DEFAULT 0 CHECK(attempt_count BETWEEN 0 AND 5),
 consumed_at timestamptz,
 revoked_at timestamptz,
 CHECK(expires_at>created_at)
);
-- MAC de código curto usa chave externa; hash simples permite brute force offline.
CREATE TABLE authentication_messages (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 password_reset_token_id uuid REFERENCES password_reset_tokens(id),
 admin_login_challenge_id uuid REFERENCES admin_login_challenges(id),
 recipient varchar(320) NOT NULL,
 payload_ciphertext bytea,
 encryption_key_id text NOT NULL,
 status text NOT NULL DEFAULT 'PENDING' CHECK(status IN ('PENDING','PROCESSING','SENT','FAILED','CANCELED')),
 created_at timestamptz NOT NULL DEFAULT now(),
 available_at timestamptz NOT NULL DEFAULT now(),
 expires_at timestamptz NOT NULL,
 locked_until timestamptz,
 lock_owner uuid,
 attempt_count integer NOT NULL DEFAULT 0 CHECK(attempt_count>=0),
 last_error text,
 provider_id text,
 CHECK(num_nonnulls(password_reset_token_id,admin_login_challenge_id)=1),
 CHECK(expires_at>created_at),
 CHECK(status NOT IN ('PENDING','PROCESSING') OR payload_ciphertext IS NOT NULL)
);
CREATE INDEX auth_messages_pending_idx ON authentication_messages(available_at,expires_at)
 WHERE status IN ('PENDING','PROCESSING');
CREATE INDEX reset_expiry_idx ON password_reset_tokens(expires_at);
CREATE INDEX challenge_expiry_idx ON admin_login_challenges(expires_at);

-- Tentativas: conta/origem derivadas por HMAC, inclusive contas inexistentes.
-- Registro de tentativa não deve ser desfeito pelo rollback da criação do pedido.
CREATE TABLE access_attempts (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 scope text NOT NULL CHECK(scope IN ('BOOKING','LOGIN','RESET','ADMIN_CODE')),
 photographer_id uuid REFERENCES photographers(id),
 subject_key bytea NOT NULL,
 origin_key bytea NOT NULL,
 succeeded boolean NOT NULL DEFAULT false,
 occurred_at timestamptz NOT NULL DEFAULT now(),
 CHECK(scope<>'BOOKING' OR photographer_id IS NOT NULL)
);
CREATE INDEX access_attempts_subject_idx ON access_attempts(scope,subject_key,occurred_at);
CREATE INDEX access_attempts_origin_idx ON access_attempts(scope,origin_key,occurred_at);

-- Spring Session JDBC padrão PostgreSQL em schema próprio.
CREATE SCHEMA authentication;
CREATE TABLE authentication.spring_session (
 primary_id char(36) PRIMARY KEY,
 session_id char(36) NOT NULL UNIQUE,
 creation_time bigint NOT NULL,
 last_access_time bigint NOT NULL,
 max_inactive_interval integer NOT NULL,
 expiry_time bigint NOT NULL,
 principal_name varchar(100)
);
CREATE INDEX spring_session_expiry_idx ON authentication.spring_session(expiry_time);
CREATE INDEX spring_session_principal_idx ON authentication.spring_session(principal_name);
CREATE TABLE authentication.spring_session_attributes (
 session_primary_id char(36) NOT NULL REFERENCES authentication.spring_session(primary_id) ON DELETE CASCADE,
 attribute_name varchar(200) NOT NULL,
 attribute_bytes bytea NOT NULL,
 PRIMARY KEY(session_primary_id,attribute_name)
);

INSERT INTO platform_settings(setting_key,integer_value) VALUES
 ('password_min_chars',15),('password_max_chars',128),('reset_ttl_seconds',1800),
 ('admin_code_digits',6),('admin_code_ttl_seconds',300),('admin_code_attempts',5),
 ('admin_code_resend_seconds',60),('admin_code_emissions',5),('admin_code_window_seconds',900),
 ('login_failures_per_account',5),('login_window_seconds',900),('login_pause_seconds',900),
 ('login_attempts_per_ip',30),('reset_per_account_hour',3),('reset_per_ip_hour',10),
 ('outbox_poll_seconds',5),('outbox_batch_size',20),('notification_concurrency',2),
 ('notification_max_attempts',5),('retry_1_seconds',60),('retry_2_seconds',300),
 ('retry_3_seconds',900),('retry_4_seconds',3600),('work_lease_seconds',120),
 ('reminder_default_minutes',1440),('photographer_idle_seconds',3600),
 ('photographer_absolute_seconds',86400),('admin_idle_seconds',900),('admin_absolute_seconds',28800);

-- RLS: contexto por SET LOCAL em transação, estabelecido somente pelo servidor.
-- Papéis NOLOGIN separados; provisionar credenciais fora do SQL/Git.
-- Instalador requer CREATEROLE. Não conceder migração/owner/BYPASSRLS aos logins.
DO $$ BEGIN
 IF NOT EXISTS(SELECT FROM pg_roles WHERE rolname='jm_tenant') THEN CREATE ROLE jm_tenant NOLOGIN NOBYPASSRLS; END IF;
 IF NOT EXISTS(SELECT FROM pg_roles WHERE rolname='jm_client') THEN CREATE ROLE jm_client NOLOGIN NOBYPASSRLS; END IF;
 IF NOT EXISTS(SELECT FROM pg_roles WHERE rolname='jm_admin') THEN CREATE ROLE jm_admin NOLOGIN NOBYPASSRLS; END IF;
 IF NOT EXISTS(SELECT FROM pg_roles WHERE rolname='jm_worker') THEN CREATE ROLE jm_worker NOLOGIN NOBYPASSRLS; END IF;
END $$;
CREATE FUNCTION request_photographer_id() RETURNS uuid LANGUAGE sql STABLE AS $$
 SELECT nullif(current_setting('app.photographer_id',true),'')::uuid
$$;
CREATE FUNCTION request_appointment_id() RETURNS uuid LANGUAGE sql STABLE AS $$
 SELECT nullif(current_setting('app.appointment_id',true),'')::uuid
$$;
-- Não usar um login comum que possa SET ROLE para todos os perfis.
-- Admin e worker possuem contextos de confiança separados e auditados no domínio.
DO $$ DECLARE t text; BEGIN
 FOREACH t IN ARRAY ARRAY['photographer_users','services','weekly_schedule','calendar_blocks',
 'appointments','calendar_occupancy','appointment_events','appointment_access_tokens',
 'blocked_contacts','subscriptions','payments','outbox_events','notifications',
 'notification_attempts','push_subscriptions','appointment_reminders'] LOOP
  EXECUTE format('ALTER TABLE scheduling.%I ENABLE ROW LEVEL SECURITY',t);
  EXECUTE format('ALTER TABLE scheduling.%I FORCE ROW LEVEL SECURITY',t);
  EXECUTE format('CREATE POLICY tenant_scope ON scheduling.%I TO jm_tenant USING(photographer_id=scheduling.request_photographer_id()) WITH CHECK(photographer_id=scheduling.request_photographer_id())',t);
  EXECUTE format('CREATE POLICY privileged_scope ON scheduling.%I TO jm_admin,jm_worker USING(true) WITH CHECK(true)',t);
 END LOOP;
END $$;
ALTER TABLE photographers ENABLE ROW LEVEL SECURITY;
ALTER TABLE photographers FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_scope ON photographers TO jm_tenant
 USING(id=request_photographer_id()) WITH CHECK(id=request_photographer_id());
CREATE POLICY privileged_scope ON photographers TO jm_admin,jm_worker USING(true) WITH CHECK(true);
CREATE POLICY client_read ON appointments FOR SELECT TO jm_client
 USING(photographer_id=request_photographer_id() AND id=request_appointment_id());
CREATE POLICY client_history ON appointment_events FOR SELECT TO jm_client
 USING(photographer_id=request_photographer_id() AND appointment_id=request_appointment_id());
-- Contexto client só após validação do hash. Política não autoriza mutações públicas.
-- Bootstrap de login, catálogo/disponibilidade públicos, ações client, sucessora e
-- busca de token: implementar comandos/projeções restritos antes de abrir endpoints.
-- Falha fechada: jm_client não recebe leitura geral nem DML.
GRANT USAGE ON SCHEMA scheduling TO jm_tenant,jm_client,jm_admin,jm_worker;
GRANT SELECT ON photographers,services,weekly_schedule,calendar_blocks,appointments,
 calendar_occupancy,appointment_events,blocked_contacts,subscriptions,payments,
 notifications,notification_attempts,push_subscriptions,appointment_reminders TO jm_tenant;
GRANT INSERT,UPDATE ON services,weekly_schedule,calendar_blocks,appointments,
 blocked_contacts,push_subscriptions TO jm_tenant;
GRANT DELETE ON weekly_schedule,calendar_blocks,push_subscriptions TO jm_tenant;
GRANT INSERT ON appointment_events,outbox_events TO jm_tenant;
GRANT SELECT ON appointments,appointment_events TO jm_client;
-- Triggers de ocupação precisam DML derivado sem DML direto pelo tenant.
-- Funções estreitas SECURITY DEFINER; dono de instalação deve conseguir escrever
-- através de RLS (superuser/BYPASSRLS). Seu login não é entregue à aplicação.
ALTER FUNCTION sync_appointment_occupancy() SECURITY DEFINER;
ALTER FUNCTION sync_appointment_occupancy() SET search_path=scheduling,pg_temp;
ALTER FUNCTION sync_block_occupancy() SECURITY DEFINER;
ALTER FUNCTION sync_block_occupancy() SET search_path=scheduling,pg_temp;
REVOKE EXECUTE ON FUNCTION sync_appointment_occupancy(),sync_block_occupancy() FROM PUBLIC;
GRANT SELECT ON ALL TABLES IN SCHEMA scheduling TO jm_admin,jm_worker;
GRANT INSERT,UPDATE ON photographers,appointments,blocked_contacts,subscriptions,payments,
 payment_webhook_events,outbox_events,notifications,notification_attempts,appointment_reminders TO jm_admin,jm_worker;
GRANT INSERT ON appointment_events,admin_audit_log TO jm_admin,jm_worker;
GRANT UPDATE ON platform_settings TO jm_admin;
GRANT DELETE ON calendar_occupancy TO jm_worker;
-- Autenticação/sessões e access_attempts: grants específicos só ao provisionar
-- serviço autenticador; jamais expor as tabelas aos papéis tenant/client.
-- Não conceder UPDATE/DELETE em históricos a papéis operacionais.
COMMIT;
-- Não representa aplicação implementada nem política LGPD aprovada.
-- Validar integração Spring/JPA/RLS e privilégios de funções antes de produção.
