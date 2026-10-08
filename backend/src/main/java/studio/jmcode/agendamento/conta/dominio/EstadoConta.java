package studio.jmcode.agendamento.conta.dominio;

public enum EstadoConta {
    EM_TESTE, ATIVA, SUSPENSA, CANCELADA;

    public boolean podeCriarSolicitacao() {
        return this == EM_TESTE || this == ATIVA;
    }
    public boolean podeAnalisarPendencia() {
        return this == EM_TESTE || this == ATIVA || this == SUSPENSA;
    }
    public boolean podeProporNovaData() {
        return podeCriarSolicitacao();
    }
    public boolean podeConsultarCompromissos() {
        return true; // Acesso em CANCELADA depende de retenção BT-001 e bloqueio de segurança.
    }
}
