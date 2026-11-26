# Instalador de Inventario para Linux

Repositorio del instalador del agente de inventario para Linux Mint/Ubuntu x86_64.

Versión actual: **0.3.1** (25 de noviembre de 2026).

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

## Opción solo instalador

Si solo necesitas el archivo y no el resto del repositorio:

```bash
mkdir -p /home/soporte/inv-0.3.1 && cd /home/soporte/inv-0.3.1
curl -fsSLO https://github.com/JulioDyD/instalador-inventario-linux/releases/latest/download/instalar-inventario-linux.sh
curl -fsSLO https://github.com/JulioDyD/instalador-inventario-linux/releases/latest/download/instalar-inventario-linux.sh.sha256
sha256sum -c instalar-inventario-linux.sh.sha256
sudo bash instalar-inventario-linux.sh
```

El repositorio `instalador-inventario-linux-dist` quedó archivado. Este repositorio es la fuente única y se actualizará con cada versión.

## Importante: la ejecución normal hace una reinstalación limpia

La versión 0.3.1 realiza un reset local total antes de instalar. Elimina la aplicación, el venv, los runtimes anteriores, la configuración y la identidad en:

```text
/opt/inventario-telemetria
/etc/inventario-telemetria
/var/lib/inventario-telemetria
```

También sustituye `telemetry-agent.service` y elimina sus drop-ins. Conserva los logs y la cuenta `telemetry-agent`.

El reset no es reversible con la identidad anterior. Si una fase posterior falla, la instalación previa ya no queda disponible para seguir funcionando. El instalador debe corregirse o repetirse después de resolver el diagnóstico.

Al borrar la identidad local se generan un UUID y un token nuevos. Es necesario introducir otra vez el código INV y aprobar el nuevo registro en el panel. La ficha anterior no se elimina automáticamente y puede quedar otra ficha del mismo equipo.

## Durante la instalación

1. El script verifica el ZIP incorporado, el runtime, los SHA-256 y el receptor HTTPS.
2. Solicita el código INV. El código se obtiene de la plataforma, se escribe visible y no se guarda en la bitácora.
3. Instala Python portátil 3.12.16 aislado en `/opt` y prueba su ejecución como `telemetry-agent`.
4. Instala y habilita `telemetry-agent.service`.
5. Confirma el UUID y el estado inicial del equipo.
6. Ingresar al panel de inventario, abrir Solicitudes, revisar la compañía/sede y aprobar el nuevo registro.
7. Esperar el siguiente ciclo y comprobar que el equipo aparezca En línea.

Panel: https://inventario-equipos-dyd-261117.web.app

## Contenido del repositorio

- `instalar-inventario-linux.sh`: instalador completo y autocontenido. Es lo único necesario para instalar.
- `instalar-inventario-linux.sh.sha256`: huella del instalador.
- `agente/`: ZIP del agente 0.3.1 y su huella. El instalador ya lo incluye embebido.
- `documentacion/`: guía del agente 0.3.1 y bitácoras históricas de 0.2.0.
- `CAMBIOS.txt`, `CONTENIDO.txt`, `LEEME.txt`, `VERIFICACION.txt` y `SHA256SUMS.txt`: documentación y verificación del paquete.

## Verificación

Huella esperada del instalador 0.3.1:

```text
a996ce64db54d704f1e10b618bb1e41201770ec34d2ebcfcc9339c659c66558c
```

Comprobar el paquete sin instalar nada:

```bash
bash instalar-inventario-linux.sh --check
```

Revisar una instalación existente sin borrar, reiniciar ni instalar:

```bash
bash instalar-inventario-linux.sh --verify
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
