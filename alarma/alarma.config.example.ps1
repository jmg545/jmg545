# Copia este archivo como  alarma.config.ps1  y rellena tus valores.
# alarma.config.ps1 NO se sube al repositorio (esta en .gitignore).
@{
    # A donde se publica la orden. Un solo POST con el JSON en el cuerpo.
    #   Internet (recomendado):  https://ntfy.sh/<topic-secreto-aleatorio>
    #   Solo Wi-Fi de casa:      http://192.168.1.50:1821/alarma
    Endpoint = 'https://ntfy.sh/CAMBIA-ESTO-topic-aleatorio'

    # Secreto compartido con Tasker. Tasker descarta todo mensaje que no lo lleve.
    Token = 'CAMBIA-ESTO-token-aleatorio'

    # Opcional. Solo si usas una cuenta ntfy con token de acceso:
    #   AuthHeader = 'Bearer tk_xxxxxxxxxxxxxxxx'
    AuthHeader = ''
}
