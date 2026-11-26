# Instalador de Inventario para Linux

Repositorio del instalador del agente de inventario para Linux Mint/Ubuntu x86_64.

## Requisitos

- Linux Mint o Ubuntu x86_64.
- systemd y glibc 2.17 o superior.
- Permisos `sudo`.
- Acceso a Internet para GitHub, PyPI y el receptor HTTPS.
- Terminal interactiva: el instalador pide el código INV al ejecutarse.

## Descargar e instalar en una sede

Una sola línea descarga el repositorio completo, verifica los archivos y ejecuta el instalador:

```bash
cd /home/soporte && git clone --depth 1 https://github.com/JulioDyD/instalador-inventario-linux.git && cd instalador-inventario-linux && sha256sum -c SHA256SUMS.txt && sudo bash instalar-inventario-linux.sh
```

Si `git` no está instalado:

```bash
sudo apt-get update && sudo apt-get install -y git
```

También se puede descargar el ZIP del repositorio:

```bash
cd /home/soporte && curl -fsSL -o repo.zip https://github.com/JulioDyD/instalador-inventario-linux/archive/refs/heads/main.zip && unzip -q repo.zip && cd instalador-inventario-linux-main && sha256sum -c SHA256SUMS.txt && sudo bash instalar-inventario-linux.sh
```

## Durante la instalación

1. El script verifica el paquete incluido y el receptor HTTPS.
2. Si el Python del sistema no es compatible, descarga Python 3.12.16 aislado en `/opt`.
3. Solicita el código INV. El código se obtiene de la plataforma y se pega en ese momento.
4. Instala y habilita `telemetry-agent.service`.
5. Confirma el UUID y el estado inicial del equipo.
6. Ingresar al panel de inventario, abrir Solicitudes, revisar la compañía/sede y aprobar el equipo.
7. Esperar el siguiente ciclo y comprobar que el equipo aparezca En línea.

Panel: https://inventario-equipos-dyd-261117.web.app

## Contenido del repositorio

- `instalar-inventario-linux.sh`: instalador completo y autocontenido. Es lo único necesario para instalar.
- `instalar-inventario-linux.sh.sha256`: huella del instalador.
- `agente/`: ZIP del agente y su huella. El instalador ya lo incluye embebido.
- `documentacion/`: bitácoras de instalación y guía de referencia.
- `LEEME.txt`, `VERIFICACION.txt` y `SHA256SUMS.txt`: documentación y verificación del paquete.

## Verificación

La huella esperada del instalador versión 0.2.0 es:

```text
ca0e2313bda988d08e3fe76e5b12cb39138244194ffc5deb76d232e47732a70d
```

Comprobar el paquete sin instalar nada:

```bash
bash instalar-inventario-linux.sh --check
```

Verificar todos los archivos del repositorio:

```bash
sha256sum -c SHA256SUMS.txt
```

## Comandos útiles después de instalar

```bash
sudo systemctl status telemetry-agent.service --no-pager
sudo systemctl is-enabled telemetry-agent.service
sudo journalctl -u telemetry-agent.service -n 30 --no-pager
```

## Notas de seguridad

- El repositorio y su documentación son públicos. No agregar códigos INV, claves, tokens ni credenciales.
- El código INV se solicita al ejecutar el instalador y no se guarda en este repositorio.
- No ejecutar el instalador con `curl | bash`: requiere terminal interactiva y debe descargarse primero.
- El equipo queda pendiente hasta que se apruebe en Solicitudes del panel.
