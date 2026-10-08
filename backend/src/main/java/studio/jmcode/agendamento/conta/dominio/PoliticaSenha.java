package studio.jmcode.agendamento.conta.dominio;

public final class PoliticaSenha {
    private PoliticaSenha() { }
    public static void validarFormato(String senha) {
        if (senha == null || senha.length() < 15 || senha.length() > 128) {
            throw new IllegalArgumentException("Senha deve conter entre 15 e 128 caracteres.");
        }
        // Não fazer trim: espaços e frases são permitidos pela baseline.
        // Validação de senha comprometida é obrigatória antes da disponibilização pública.
    }
}
