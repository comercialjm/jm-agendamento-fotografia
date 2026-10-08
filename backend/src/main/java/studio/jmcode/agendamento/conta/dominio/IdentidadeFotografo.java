package studio.jmcode.agendamento.conta.dominio;

import java.util.Locale;

public final class IdentidadeFotografo {
    private IdentidadeFotografo() { }

    public static String normalizarEmail(String email) {
        if (email == null || email.isBlank()) throw new IllegalArgumentException("E-mail obrigatório.");
        String value = email.strip().toLowerCase(Locale.ROOT);
        if (value.length() > 320 || !value.matches("[^\\s@]+@[^\\s@]+\\.[^\\s@]+"))
            throw new IllegalArgumentException("E-mail inválido.");
        return value;
    }
    public static String validarSlug(String slug) {
        if (slug == null || !slug.matches("[a-z0-9](?:[a-z0-9-]{1,98}[a-z0-9])?"))
            throw new IllegalArgumentException("Identificador público inválido.");
        return slug;
    }
}
