package studio.jmcode.agendamento.conta.aplicacao;

import java.time.Clock;
import java.time.Instant;
import java.time.ZoneId;
import java.util.Objects;
import java.util.UUID;
import studio.jmcode.agendamento.conta.dominio.IdentidadeFotografo;
import studio.jmcode.agendamento.conta.dominio.PoliticaSenha;

/** Caso de uso sem endpoint público até conclusão de identidade/RLS/antiabuso. */
public final class CadastroFotografo {
    private final CadastroPort porta;
    private final PasswordHasher hasher;
    private final SenhasComprometidas verificador;
    private final Clock clock;

    public CadastroFotografo(CadastroPort porta, PasswordHasher hasher,
                             SenhasComprometidas verificador, Clock clock) {
        this.porta = Objects.requireNonNull(porta);
        this.hasher = Objects.requireNonNull(hasher);
        this.verificador = Objects.requireNonNull(verificador);
        this.clock = Objects.requireNonNull(clock);
    }

    public UUID executar(ComandoCadastro comando) {
        Objects.requireNonNull(comando);
        String email = IdentidadeFotografo.normalizarEmail(comando.email());
        String slug = IdentidadeFotografo.validarSlug(comando.slug());
        PoliticaSenha.validarFormato(comando.senha());
        ZoneId.of(comando.timezone());
        if (comando.nome() == null || comando.nome().isBlank() || comando.nome().length() > 150)
            throw new IllegalArgumentException("Nome inválido.");
        if (verificador.ehComprometida(comando.senha()))
            throw new IllegalArgumentException("Senha não permitida.");
        Instant inicio = clock.instant();
        String hash = hasher.hash(comando.senha());
        // Porta deve implementar atomicidade: photographers + photographer_users + subscriptions.
        return porta.criar(new CadastroPreparado(
            comando.nome().strip(), email, slug, comando.timezone(), hash, inicio, inicio.plus(java.time.Duration.ofDays(30))));
    }

    public record ComandoCadastro(String nome, String email, String slug, String timezone, String senha) { }
    public record CadastroPreparado(String nome, String emailNormalizado, String slug,
                                   String timezone, String hashSenha, Instant inicioTeste, Instant fimTeste) { }
    public interface CadastroPort { UUID criar(CadastroPreparado preparado); }
    public interface PasswordHasher { String hash(String senha); }
    public interface SenhasComprometidas { boolean ehComprometida(String senha); }
}
