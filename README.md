# Instalador de Inventario para Linux

Repositorio privado del instalador del agente de inventario para equipos Linux Mint/Ubuntu x86_64.

## Requisitos

- Linux Mint o Ubuntu x86_64.
- systemd y glibc 2.17 o superior.
- Permisos `sudo`.
- Acceso a Internet para GitHub, PyPI y el receptor HTTPS.
- Terminal interactiva: el instalador pide el código INV al ejecutarse.

## Acceso al repositorio

Este repositorio es privado. Para descargar el instalador se necesita un token de GitHub de solo lectura, creado así:

1. GitHub -> Settings -> Developer settings -> Personal access tokens -> Fine-grained tokens -> Generate new token.
2. Repository access: Only select repositories -> este repositorio.
3. Permissions -> Contents: Read-only.
4. Expiración recomendada: entre 30 y 90 días.
5. Copiar el token una sola vez y entregarlo únicamente a las sedes autorizadas.

El token es un secreto. No debe escribirse en el README, en el repositorio, en Git ni en archivos compartidos de forma pública. Si se filtra, debe revocarse y generar uno nuevo.

## Descarga y ejecución en cada sede

Reemplazar `<USUARIO>`, `<REPO>` y `<REF>` por los datos del repositorio. `<REF>` puede ser `v0.2.0` o `main`.

```bash
OWNER="<USUARIO>"; REPO="<REPO>"; REF="<REF>"
read -rsp "Token GitHub: " GH_TOKEN; echo
BASE="https://api.github.com/repos/$OWNER/$REPO/contents"
curl -fsSL --proto '=https' -H "Authorization: Bearer $GH_TOKEN" \
  -H "Accept: application/vnd.github.raw" \
  "$BASE/instalar-inventario-linux.sh?ref=$REF" -o instalar-inventario-linux.sh
curl -fsSL --proto '=https' -H "Authorization: Bearer $GH_TOKEN" \
  -H "Accept: application/vnd.github.raw" \
  "$BASE/instalar-inventario-linux.sh.sha256?ref=$REF" -o instalar-inventario-linux.sh.sha256
unset GH_TOKEN
sha256sum -c instalar-inventario-linux.sh.sha256
sudo bash instalar-inventario-linux.sh
```

El token se solicita de forma oculta para que no quede en el historial del shell.

## Durante la instalación

1. El script verifica el paquete incluido y el receptor HTTPS.
2. Si el Python del sistema no es compatible, descarga Python 3.12.16 aislado en `/opt`.
3. Solicita el código INV. El código se ve al escribirlo.
4. Instala y habilita `telemetry-agent.service`.
5. Confirma el UUID y el estado inicial del equipo.
6. Ingresar al panel de inventario, abrir Solicitudes, revisar la compañía/sede y aprobar el equipo.
7. Esperar el siguiente ciclo y comprobar que el equipo aparezca En línea.

Panel: https://inventario-equipos-dyd-261117.web.app

## Verificación

La huella esperada del instalador versión 0.2.0 es:

```
ca0e2313bda988d08e3fe76e5b12cb39138244194ffc5deb76d232e47732a70d
```

Comprobar el paquete sin instalar nada:

```bash
bash instalar-inventario-linux.sh --check
```

## Comandos útiles

```bash
sudo systemctl status telemetry-agent.service --no-pager
sudo systemctl is-enabled telemetry-agent.service
sudo journalctl -u telemetry-agent.service -n 30 --no-pager
```

## Seguridad

- El repositorio incluye documentación interna con IPs, hostnames y UUIDs de equipos. No compartir el token ni el repositorio fuera del personal autorizado.
- El token compartido permite leer todo el repositorio. Si se requiere auditoría por persona, usar un token por sede o invitarlos como colaboradores.
- No ejecutar el instalador con `curl | bash`: requiere terminal interactiva y debe descargarse primero.
