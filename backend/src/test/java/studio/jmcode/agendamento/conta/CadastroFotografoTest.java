package studio.jmcode.agendamento.conta;

import org.junit.jupiter.api.Test;
import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicReference;
import studio.jmcode.agendamento.conta.aplicacao.CadastroFotografo;
import studio.jmcode.agendamento.conta.dominio.EstadoConta;
import studio.jmcode.agendamento.conta.dominio.PoliticaSenha;
import static org.junit.jupiter.api.Assertions.*;

class CadastroFotografoTest {
    @Test void cadastroPreparaTesteDeTrintaDiasESemAlterarEspacosDaSenha() {
        AtomicReference<CadastroFotografo.CadastroPreparado> gravado = new AtomicReference<>();
        UUID esperado = UUID.randomUUID();
        CadastroFotografo caso = new CadastroFotografo(
            dados -> { gravado.set(dados); return esperado; },
            senha -> "hash-do-teste", senha -> false,
            Clock.fixed(Instant.parse("2026-10-08T12:00:00Z"), ZoneOffset.UTC));
        UUID id = caso.executar(new CadastroFotografo.ComandoCadastro(
            " Foto Exemplo ", "FOTO@EXEMPLO.COM", "foto-exemplo", "America/Sao_Paulo", "frase longa com espaços"));
        assertEquals(esperado, id);
        assertEquals("foto@exemplo.com", gravado.get().emailNormalizado());
        assertEquals("Foto Exemplo", gravado.get().nome());
        assertEquals(Instant.parse("2026-11-07T12:00:00Z"), gravado.get().fimTeste());
    }
    @Test void senhaCurtaERejeitada() {
        assertThrows(IllegalArgumentException.class, () -> PoliticaSenha.validarFormato("curta"));
    }
    @Test void suspensaNaoRecebeNovoPedidoMasAnalisaPendente() {
        assertFalse(EstadoConta.SUSPENSA.podeCriarSolicitacao());
        assertTrue(EstadoConta.SUSPENSA.podeAnalisarPendencia());
        assertFalse(EstadoConta.SUSPENSA.podeProporNovaData());
    }
}
