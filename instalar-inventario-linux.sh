#!/usr/bin/env bash
# Instalador autocontenido del agente. Generado por package-linux-installer.py.
set +x
set -Eeuo pipefail
umask 077

AGENT_VERSION="0.2.0"
PACKAGE_SHA256="95f7c6985e3bbdbf835c264239789f9cdd6a14901189f0efe4499f0f248f2331"
SERVER_URL="https://inventario-api-jryilooe3a-uc.a.run.app"
PANEL_URL="https://inventario-equipos-dyd-261117.web.app"
SYSTEM_PATH="/usr/sbin:/usr/bin:/sbin:/bin"
export PATH="$SYSTEM_PATH"
INSTALL_DIR="/opt/inventario-telemetria"
CONFIG_FILE="/etc/inventario-telemetria/agent.json"
IDENTITY_FILE="/var/lib/inventario-telemetria/identity.json"
RUNTIME_DIR="$INSTALL_DIR/python-3.12.16"
RUNTIME_URL="https://github.com/astral-sh/python-build-standalone/releases/download/20261123/cpython-3.12.16%2B20261123-x86_64-unknown-linux-gnu-install_only_stripped.tar.gz"
RUNTIME_SHA256="c85811d35971d06612585a057db3b71806378df6ea8476275fb16aa5c9fe56a0"
SELF_PATH="$(readlink -f -- "${BASH_SOURCE[0]}")"
WORK_DIR=""
VENV_BACKUP=""
INSTALLER_DONE=0
STEP="preparación"
CONFIG_HASH=""
IDENTITY_HASH=""
LOG_FILE=""

usage() {
  cat <<'HELP'
Instalador completo de inventario para Linux Mint/Ubuntu x86_64 con systemd.

Uso: bash instalar-inventario-linux.sh
     bash instalar-inventario-linux.sh --check

El archivo ya incluye el agente; necesita Internet para sus dependencias.
Solicita sudo si hace falta. En una instalación nueva pide el código INV
mediante entrada visible. Puede dejarlo vacío para usar una clave general.
Si Python del sistema no dispone de un venv compatible, prepara Python 3.12.16
aislado en /opt. Conserva configuración e identidad de instalaciones anteriores.

--check  Verifica el paquete incluido, sin sudo, red ni instalar servicios.
--help   Muestra esta ayuda.

Después de instalar, apruebe el equipo en Solicitudes del panel de inventario.
HELP
}

fail() { printf '\nERROR: %s\n' "$*" >&2; return 1; }
step() { STEP="$1"; printf '\n=== %s ===\n' "$STEP"; }

cleanup() {
  local rc=$?
  trap - EXIT
  set +e
  if ((rc != 0)) && [[ -n "$VENV_BACKUP" ]] && ((INSTALLER_DONE == 0)); then
    if [[ -e "$INSTALL_DIR/venv" ]]; then
      mv -- "$INSTALL_DIR/venv" "$INSTALL_DIR/venv.fallido-$(date +%Y%m%d-%H%M%S)-$$"
    fi
    if mv -- "$VENV_BACKUP" "$INSTALL_DIR/venv"; then
      printf 'Se restauró el entorno virtual anterior.\n'
    fi
  fi
  if [[ -n "$WORK_DIR" && -d "$WORK_DIR" ]]; then rm -rf -- "$WORK_DIR"; fi
  if ((rc != 0)) && [[ -n "$LOG_FILE" ]]; then
    printf '\nProceso interrumpido en: %s. Registro: %s\n' "$STEP" "$LOG_FILE"
  fi
  exit "$rc"
}

extract_package() {
  local script_file="$1" destination="$2"
  python3 -I - "$script_file" "$destination" "$PACKAGE_SHA256" "$AGENT_VERSION" <<'PY'
import base64, hashlib, io, pathlib, stat, sys, zipfile
source, destination, expected, version = sys.argv[1:]
marker = b"\n__INVENTARIO_AGENT_ZIP_BASE64__\n"
try:
    data = pathlib.Path(source).read_bytes().split(marker, 1)[1]
    payload = base64.b64decode(b"".join(data.split()), validate=True)
    if hashlib.sha256(payload).hexdigest() != expected:
        raise ValueError("hash")
    root = pathlib.Path(destination)
    prefix = "inventario-agente-" + version
    with zipfile.ZipFile(io.BytesIO(payload)) as archive:
        names = archive.namelist()
        if len(names) != len(set(names)):
            raise ValueError("duplicate")
        for item in archive.infolist():
            path = pathlib.PurePosixPath(item.filename)
            if (path.is_absolute() or ".." in path.parts or not path.parts
                    or path.parts[0] != prefix
                    or stat.S_ISLNK(item.external_attr >> 16)):
                raise ValueError("path")
        archive.extractall(root)
    package = root / prefix
    manifest = (package / "MANIFEST.sha256").read_text().splitlines()
    listed = set()
    for line in manifest:
        digest, name = line.split("  ", 1)
        path = pathlib.PurePosixPath(name)
        if path.is_absolute() or ".." in path.parts or name in listed:
            raise ValueError("manifest")
        listed.add(name)
        if hashlib.sha256((package / name).read_bytes()).hexdigest() != digest:
            raise ValueError("file")
    files = {str(p.relative_to(package)) for p in package.rglob("*") if p.is_file()}
    if files != listed | {"MANIFEST.sha256"}:
        raise ValueError("unlisted")
    if "scripts/install-linux.sh" not in listed or "pyproject.toml" not in listed:
        raise ValueError("missing")
except (OSError, ValueError, IndexError, KeyError, zipfile.BadZipFile):
    raise SystemExit("El paquete incluido está incompleto o no supera la verificación SHA-256.")
print("Paquete del agente " + version + ": SHA-256 y manifiesto verificados.")
PY
}

ensure_dependencies() {
  local packages=() name
  command -v python3 >/dev/null || packages+=(python3)
  command -v curl >/dev/null || packages+=(curl)
  [[ -s /etc/ssl/certs/ca-certificates.crt ]] || packages+=(ca-certificates)
  if ((${#packages[@]})); then
    command -v apt-get >/dev/null || fail "Instale python3, curl y ca-certificates antes de continuar."
    apt-get update
    apt-get install -y --no-install-recommends "${packages[@]}"
  fi
  for name in python3 curl tar sha256sum systemctl install useradd getent runuser tee df; do
    command -v "$name" >/dev/null || fail "Falta el comando requerido: $name"
  done
}

check_existing_installation() {
  if [[ -L "$CONFIG_FILE" || -L "$IDENTITY_FILE" || -L "$INSTALL_DIR/venv" ]]; then
    fail "Las rutas de configuración, identidad y entorno deben ser propias de esta instalación."
  fi
  if [[ -e "$IDENTITY_FILE" && ! -e "$CONFIG_FILE" ]]; then
    fail "Existe una identidad sin configuración. Se conserva; restaure la configuración antes de continuar."
  fi
  if [[ -e "$CONFIG_FILE" ]]; then
    python3 -I - "$CONFIG_FILE" "$SERVER_URL" "$IDENTITY_FILE" <<'PY'
import json, pathlib, sys
filename, expected_url, expected_state = sys.argv[1:]
try:
    raw = json.loads(pathlib.Path(filename).read_text())
    if raw.get("server_url", "").rstrip("/") != expected_url:
        raise ValueError()
    state = pathlib.Path(raw.get("state_path", "state/identity.json"))
    if not state.is_absolute():
        state = pathlib.Path(filename).parent / state
    if state.resolve() != pathlib.Path(expected_state).resolve():
        raise ValueError()
except (OSError, ValueError, TypeError, AttributeError):
    raise SystemExit("Configuración existente inválida o de otro receptor/ruta. Se conserva sin modificar; revise su instalación.")
print("Configuración existente: se conservan el receptor, la identidad y la asignación del equipo.")
PY
    CONFIG_HASH="$(sha256sum "$CONFIG_FILE" | cut -d ' ' -f 1)"
  elif [[ ! -t 0 ]]; then
    fail "Ejecute este archivo en una terminal interactiva para introducir el código de instalación."
  fi
  if [[ -e "$IDENTITY_FILE" ]]; then
    IDENTITY_HASH="$(sha256sum "$IDENTITY_FILE" | cut -d ' ' -f 1)"
  fi
}

usable_python() {
  local candidate="$1" probe
  [[ -x "$candidate" ]] || return 1
  "$candidate" -I -c 'import sys,ssl,venv,ensurepip; sys.exit(0 if sys.version_info >= (3,10) else 1)' >/dev/null 2>&1 || return 1
  probe="$(mktemp -d "$WORK_DIR/probe.XXXXXX")" || return 1
  "$candidate" -I -m venv "$probe/venv" >/dev/null 2>&1 || return 1
  "$probe/venv/bin/python" -I -m pip --version >/dev/null 2>&1
}

select_python() {
  if usable_python /usr/bin/python3; then
    PYTHON_BIN=/usr/bin/python3
    printf 'Se utilizará Python del sistema: '
    "$PYTHON_BIN" --version
    return
  fi
  if [[ -e "$RUNTIME_DIR" ]]; then
    usable_python "$RUNTIME_DIR/bin/python3" || fail "El runtime aislado existente no funciona. Se conserva para revisión."
  else
    printf 'Se preparará Python 3.12.16 aislado; el Python del sistema se conserva.\n'
    curl --fail --location --proto '=https' --proto-redir '=https' \
      --retry 2 --connect-timeout 15 --max-time 300 \
      --output "$WORK_DIR/python.tar.gz.part" "$RUNTIME_URL"
    printf '%s  %s\n' "$RUNTIME_SHA256" "$WORK_DIR/python.tar.gz.part" | sha256sum -c -
    install -d -m 0700 "$WORK_DIR/runtime"
    tar -xzf "$WORK_DIR/python.tar.gz.part" --no-same-owner -C "$WORK_DIR/runtime"
    install -d -o root -g root -m 0755 "$INSTALL_DIR"
    mv -- "$WORK_DIR/runtime/python" "$RUNTIME_DIR"
    chown -R root:root "$RUNTIME_DIR"
    chmod -R go-w "$RUNTIME_DIR"
    usable_python "$RUNTIME_DIR/bin/python3" || fail "No se pudo preparar el runtime de Python."
  fi
  PYTHON_BIN="$RUNTIME_DIR/bin/python3"
  "$PYTHON_BIN" --version
}

prepare_existing_venv() {
  [[ -e "$INSTALL_DIR/venv" || -L "$INSTALL_DIR/venv/bin/python" ]] || return 0
  if "$INSTALL_DIR/venv/bin/python" -I -c 'import sys,ssl; sys.exit(0 if sys.version_info >= (3,10) else 1)' >/dev/null 2>&1 \
      && "$INSTALL_DIR/venv/bin/python" -I -m pip --version >/dev/null 2>&1; then
    return
  fi
  if systemctl is-active --quiet telemetry-agent.service; then
    fail "El servicio existente está activo con un entorno incompatible. Se conserva; requiere una actualización asistida."
  fi
  VENV_BACKUP="$INSTALL_DIR/venv.respaldo-$(date +%Y%m%d-%H%M%S)-$$"
  mv -- "$INSTALL_DIR/venv" "$VENV_BACKUP"
  printf 'Entorno parcial incompatible conservado en: %s\n' "$VENV_BACKUP"
}

install_agent() {
  local installer="$WORK_DIR/inventario-agente-$AGENT_VERSION/scripts/install-linux.sh"
  if [[ -e "$CONFIG_FILE" ]]; then
    env PATH="$(dirname -- "$PYTHON_BIN"):$SYSTEM_PATH" /bin/bash "$installer" --server-url "$SERVER_URL"
    return
  fi
  local installation_code="" enrollment_key="" rc=0
  read -r -p 'Código de instalación INV (visible; Enter para inventario general): ' installation_code \
    || { fail "No se pudo leer el código de instalación."; return 1; }
  if [[ -z "$installation_code" ]]; then
    read -r -s -p 'Clave general de inscripción: ' enrollment_key \
      || { fail "No se pudo leer la clave general."; return 1; }
    printf '\n'
  fi
  # El código se ve por el eco de la terminal. Se entrega al instalador por
  # stdin, sin guardarlo en argumentos, archivos temporales ni la bitácora.
  if printf '%s\n%s\n' "$installation_code" "$enrollment_key" \
      | env PATH="$(dirname -- "$PYTHON_BIN"):$SYSTEM_PATH" /bin/bash "$installer" --server-url "$SERVER_URL"; then
    rc=0
  else
    rc=$?
  fi
  unset installation_code enrollment_key
  return "$rc"
}

check_registration() {
  runuser -u telemetry-agent -- "$INSTALL_DIR/venv/bin/python" -I - "$CONFIG_FILE" <<'PY'
import json, pathlib, sys, time
from telemetry_agent.client import APIClient, RemoteError
from telemetry_agent.config import AgentError, Config, Identity
try:
    config = Config.load(pathlib.Path(sys.argv[1]))
    for attempt in range(8):
        if config.state_path.is_file():
            identity = Identity.load_existing(config.state_path)
            try:
                result = APIClient(config, identity).get_status()
            except RemoteError as error:
                if error.status != 404:
                    raise
            else:
                if result.get("device_id") != identity.device_id:
                    raise AgentError("La identidad del receptor no coincide.")
                status = result.get("status")
                if status not in {"pending", "active", "disabled", "rejected"}:
                    raise AgentError("El receptor devolvió un estado no válido.")
                print("UUID del equipo: " + identity.device_id)
                print("Estado en el inventario: " + status)
                if status == "pending":
                    print("Instalación completada. Falta aprobar el equipo en Solicitudes del panel.")
                elif status == "active":
                    print("El equipo está aprobado. Compruebe la última lectura en el panel.")
                else:
                    raise AgentError("El equipo está deshabilitado o rechazado. Revise su estado en el panel.")
                break
        if attempt < 7:
            time.sleep(3)
    else:
        raise AgentError("No se confirmó la inscripción. Revise el código de instalación y el registro del servicio.")
except (AgentError, OSError, ValueError):
    raise SystemExit("No se confirmó una inscripción pendiente/activa. Revise el código y journalctl -u telemetry-agent.service. La identidad se conserva.")
PY
}

main() {
  case "${1:-}" in
    --help|-h) usage; return 0 ;;
    --check)
      (($# == 1)) || { usage >&2; return 2; }
      command -v python3 >/dev/null || fail "Se necesita python3 para verificar el paquete."
      WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/inventario-check.XXXXXXXX")"
      trap cleanup EXIT
      extract_package "$SELF_PATH" "$WORK_DIR"
      printf 'Verificación local completada. No se instalaron servicios ni se usó la red.\n'
      return 0 ;;
    "") ;;
    *) usage >&2; return 2 ;;
  esac
  (($# == 0)) || { usage >&2; return 2; }
  if ((EUID != 0)); then
    command -v sudo >/dev/null || fail "Ejecute este archivo como administrador con sudo."
    exec sudo -- /bin/bash "$SELF_PATH" "$@"
  fi
  export PATH="$SYSTEM_PATH"
  unset PYTHONPATH PYTHONHOME
  cd /
  [[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || fail "Este archivo requiere Linux x86_64."
  [[ -d /run/systemd/system ]] || fail "Se requiere un equipo iniciado con systemd."
  local glibc
  glibc="$(getconf GNU_LIBC_VERSION 2>/dev/null)" || fail "Se requiere GNU/Linux con glibc."
  [[ "$(printf '%s\n' 2.17 "${glibc##* }" | sort -V | head -n 1)" == 2.17 ]] || fail "Se requiere glibc 2.17 o superior."
  install -d -o root -g root -m 0700 /var/log/inventario-telemetria
  LOG_FILE="/var/log/inventario-telemetria/instalacion-$(date +%Y%m%d-%H%M%S)-$$.log"
  : > "$LOG_FILE"
  chmod 0600 "$LOG_FILE"
  exec > >(tee -a "$LOG_FILE") 2>&1
  WORK_DIR="$(mktemp -d /var/tmp/inventario-install.XXXXXXXX)"
  trap cleanup EXIT

  step '1. Identificar el equipo y preparar requisitos'
  date --iso-8601=seconds
  hostname
  uname -srm
  [[ ! -r /etc/os-release ]] || cat /etc/os-release
  ensure_dependencies
  [[ "$(df -Pk /opt | awk 'NR==2 {print $4}')" -ge 524288 ]] || fail "Se requieren al menos 512 MiB libres en /opt."
  check_existing_installation

  step '2. Extraer y verificar el agente incluido'
  extract_package "$SELF_PATH" "$WORK_DIR"

  step '3. Comprobar el receptor HTTPS'
  curl --fail --silent --show-error --proto '=https' --connect-timeout 15 --max-time 30 \
    --output "$WORK_DIR/health.json" "$SERVER_URL/health"
  python3 -I - "$WORK_DIR/health.json" <<'PY'
import json, sys
try:
    result = json.load(open(sys.argv[1]))
    if result.get("ok") is not True or result.get("project_id") != "inventario-equipos-dyd-261117":
        raise ValueError()
except (OSError, ValueError, AttributeError):
    raise SystemExit("El receptor no confirmó el proyecto esperado.")
print("Receptor HTTPS disponible; proyecto de inventario confirmado.")
PY

  step '4. Preparar un Python compatible'
  select_python
  prepare_existing_venv

  step '5. Instalar y habilitar el servicio'
  install_agent
  INSTALLER_DONE=1
  printf 'INSTALL_EXIT=0\n'
  [[ -z "$CONFIG_HASH" || "$(sha256sum "$CONFIG_FILE" | cut -d ' ' -f 1)" == "$CONFIG_HASH" ]] || fail "La configuración anterior cambió; revise el registro."
  [[ -z "$IDENTITY_HASH" || "$(sha256sum "$IDENTITY_FILE" | cut -d ' ' -f 1)" == "$IDENTITY_HASH" ]] || fail "La identidad anterior cambió; revise el registro."

  step '6. Verificar servicio, dependencias y conexión'
  local attempt
  for attempt in 1 2 3 4 5; do
    if systemctl is-active --quiet telemetry-agent.service; then break; fi
    sleep 2
  done
  systemctl is-active telemetry-agent.service
  systemctl is-enabled telemetry-agent.service
  runuser -u telemetry-agent -- "$INSTALL_DIR/venv/bin/python" -I -c \
    'import sys,psutil,telemetry_agent; print("Python agente: " + sys.version.split()[0]); print("Agente: " + telemetry_agent.__version__); print("psutil: " + psutil.__version__)'
  runuser -u telemetry-agent -- "$INSTALL_DIR/venv/bin/python" -I -m telemetry_agent --config "$CONFIG_FILE" --check-connection
  stat -c '%a %U %G %n' "$CONFIG_FILE"

  step '7. Confirmar inscripción e indicar la aprobación'
  check_registration
  stat -c '%a %U %G %n' "$IDENTITY_FILE"
  printf '\nPanel: %s\nEquipo: %s\n' "$PANEL_URL" "$(hostname)"
  printf 'Abra Solicitudes, revise la ubicación y apruebe este equipo. Después revise que aparezca En línea.\n'
  printf 'Estado del servicio: sudo systemctl status telemetry-agent.service --no-pager\n'
  printf 'Registro del agente: sudo journalctl -u telemetry-agent.service -n 30 --no-pager\n'
  printf 'Bitácora de esta instalación: %s\n' "$LOG_FILE"
  printf 'El servicio se inicia con el sistema. No se necesita reiniciar el equipo.\n'
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
  exit 0
fi
return 0

__INVENTARIO_AGENT_ZIP_BASE64__
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
LjIuMC9SRUFETUUubWRQSwECFAMUAAAACAAAACEA0RPpDwoBAACTAQAAMQAAAAAAAAAAAAAApIFm
DQAAaW52ZW50YXJpby1hZ2VudGUtMC4yLjAvYWdlbnQtY29uZmlnLmV4YW1wbGUuanNvblBLAQIU
AxQAAAAIAAAAIQBnZsh08wAAAH8BAAAmAAAAAAAAAAAAAACkgb8OAABpbnZlbnRhcmlvLWFnZW50
ZS0wLjIuMC9weXByb2plY3QudG9tbFBLAQIUAxQAAAAIAAAAIQBTC6dn8AoAAJcZAAAwAAAAAAAA
AAAAAADtgfYPAABpbnZlbnRhcmlvLWFnZW50ZS0wLjIuMC9zY3JpcHRzL2luc3RhbGwtbGludXgu
c2hQSwECFAMUAAAACAAAACEAeJ+2E/wKAABdIAAAMwAAAAAAAAAAAAAApIE0GwAAaW52ZW50YXJp
by1hZ2VudGUtMC4yLjAvc2NyaXB0cy9pbnN0YWxsLXdpbmRvd3MucHMxUEsBAhQDFAAAAAgAAAAh
AJiwcX9QAAAAVQAAADMAAAAAAAAAAAAAAKSBgSYAAGludmVudGFyaW8tYWdlbnRlLTAuMi4wL3Rl
bGVtZXRyeV9hZ2VudC9fX2luaXRfXy5weVBLAQIUAxQAAAAIAAAAIQBi8dt8NwgAAN8ZAAAzAAAA
AAAAAAAAAACkgSInAABpbnZlbnRhcmlvLWFnZW50ZS0wLjIuMC90ZWxlbWV0cnlfYWdlbnQvX19t
YWluX18ucHlQSwECFAMUAAAACAAAACEA9dqud0oKAACPIwAAMQAAAAAAAAAAAAAApIGqLwAAaW52
ZW50YXJpby1hZ2VudGUtMC4yLjAvdGVsZW1ldHJ5X2FnZW50L2NsaWVudC5weVBLAQIUAxQAAAAI
AAAAIQCSrTjbogYAAF8SAAA0AAAAAAAAAAAAAACkgUM6AABpbnZlbnRhcmlvLWFnZW50ZS0wLjIu
MC90ZWxlbWV0cnlfYWdlbnQvY29sbGVjdG9yLnB5UEsBAhQDFAAAAAgAAAAhAPQRdNP/DAAAay0A
ADEAAAAAAAAAAAAAAKSBN0EAAGludmVudGFyaW8tYWdlbnRlLTAuMi4wL3RlbGVtZXRyeV9hZ2Vu
dC9jb25maWcucHlQSwECFAMUAAAACAAAACEASdaZbeYbAAAaYQAAOQAAAAAAAAAAAAAApIGFTgAA
aW52ZW50YXJpby1hZ2VudGUtMC4yLjAvdGVsZW1ldHJ5X2FnZW50L3JlbW90ZV9jb250cm9sLnB5
UEsBAhQDFAAAAAgAAAAhADtRVCyWCQAAkR0AADQAAAAAAAAAAAAAAKSBwmoAAGludmVudGFyaW8t
YWdlbnRlLTAuMi4wL3RlbGVtZXRyeV9hZ2VudC90cmFuc3BvcnQucHlQSwUGAAAAAA4ADgARBQAA
qnQAAAAA
