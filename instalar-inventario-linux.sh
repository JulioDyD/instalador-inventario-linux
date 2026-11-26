#!/usr/bin/env bash
# Instalador autocontenido del agente. Generado por package-linux-installer.py.
set +x
set -Eeuo pipefail
umask 077

AGENT_VERSION="0.3.1"
PACKAGE_SHA256="fd901ee6275d26195b73300b3a0737874cf78957e2edb2855d5af699982b4737"
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
STEP="preparación"
LOG_FILE=""
INSTALLATION_CODE_VALUE=""
ENROLLMENT_KEY_VALUE=""
UNIT_FILE="/etc/systemd/system/telemetry-agent.service"
WANTS_FILE="/etc/systemd/system/multi-user.target.wants/telemetry-agent.service"

usage() {
  cat <<'HELP'
Instalador completo de inventario para Linux Mint/Ubuntu x86_64 con systemd.

Uso: bash instalar-inventario-linux.sh
     bash instalar-inventario-linux.sh --check
     bash instalar-inventario-linux.sh --verify

El archivo ya incluye el agente; necesita Internet para sus dependencias.
Solicita sudo si hace falta y pide el código INV mediante entrada visible.
Puede dejarlo vacío para usar una clave general. Verifica requisitos y descargas
antes de detener y ELIMINAR la instalación local anterior, incluida su identidad.
Reinstala Python 3.12.16 aislado en /opt y el agente desde cero. Genera un nuevo
UUID que deberá aprobar en el panel. La ficha anterior del panel permanece.
Conserva la cuenta del servicio y las bitácoras anteriores.

--check  Verifica el paquete incluido, sin sudo, red ni instalar servicios.
--verify Revisa el agente ya instalado y guarda el diagnóstico. No reinstala
         paquetes ni inicia, habilita o reinicia el servicio.
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
  unset INSTALLATION_CODE_VALUE ENROLLMENT_KEY_VALUE
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
  for name in python3 curl tar sha256sum systemctl install useradd getent runuser tee df find findmnt; do
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
  elif [[ ! -t 0 ]]; then
    fail "Ejecute este archivo en una terminal interactiva para introducir el código de instalación."
  fi
}

validate_reset_paths() {
  [[ "$INSTALL_DIR" == /opt/inventario-telemetria \
      && "$CONFIG_FILE" == /etc/inventario-telemetria/agent.json \
      && "$IDENTITY_FILE" == /var/lib/inventario-telemetria/identity.json \
      && "$UNIT_FILE" == /etc/systemd/system/telemetry-agent.service \
      && "$WANTS_FILE" == /etc/systemd/system/multi-user.target.wants/telemetry-agent.service ]] \
    || { fail "Las rutas de limpieza no corresponden a esta instalación."; return 1; }
  local path
  for path in "$INSTALL_DIR" "${CONFIG_FILE%/*}" "${IDENTITY_FILE%/*}" /etc/systemd/system "${WANTS_FILE%/*}"; do
    [[ ! -L "$path" && "$(readlink -f -- "$path")" == "$path" ]] \
      || { fail "Una ruta de instalación es un enlace o apunta a otra ubicación; no se elimina."; return 1; }
  done
}

check_execution_mount() {
  local options mount_target path mounts
  for path in /opt "$INSTALL_DIR" "${CONFIG_FILE%/*}" "${IDENTITY_FILE%/*}"; do
    [[ -e "$path" ]] || continue
    if ! options="$(findmnt -n -T "$path" -o OPTIONS)"; then
      fail "No se pudo comprobar el montaje de $path. La instalación anterior no se ha eliminado."
      return 1
    fi
    if [[ "$path" == /opt || "$path" == "$INSTALL_DIR" ]]; then
      case ",$options," in
        *,noexec,*) fail "El montaje de $path tiene noexec; debe permitir ejecutar el agente. No se ha eliminado la instalación anterior."; return 1 ;;
      esac
    fi
  done
  mounts="$(findmnt -rn -o TARGET)" \
    || { fail "No se pudo consultar la lista de montajes. La instalación anterior no se ha eliminado."; return 1; }
  while IFS= read -r mount_target; do
    for path in "$INSTALL_DIR" "${CONFIG_FILE%/*}" "${IDENTITY_FILE%/*}"; do
      case "$mount_target" in
        "$path"|"$path"/*) fail "Hay un montaje dentro de $path; revise esa instalación antes de eliminarla."; return 1 ;;
      esac
    done
  done <<< "$mounts"
}

collect_installation_credentials() {
  [[ -t 0 ]] || { fail "Ejecute el instalador en una terminal interactiva para introducir el código."; return 1; }
  read -r -p 'Código de instalación INV (visible; Enter para inventario general): ' INSTALLATION_CODE_VALUE \
    || { fail "No se pudo leer el código de instalación."; return 1; }
  if [[ -z "$INSTALLATION_CODE_VALUE" ]]; then
    read -r -s -p 'Clave general de inscripción: ' ENROLLMENT_KEY_VALUE \
      || { fail "No se pudo leer la clave general."; return 1; }
    printf '\n'
  fi
  printf '%s\0%s' "$INSTALLATION_CODE_VALUE" "$ENROLLMENT_KEY_VALUE" | python3 -I -c '
import re, sys
code, key = sys.stdin.read().split("\0")
if code and not re.fullmatch(r"INV-[A-Za-z0-9_-]{32}", code):
    raise SystemExit("El código debe tener el formato INV- seguido de 32 caracteres. No se ha eliminado la instalación anterior.")
if not code and not key:
    raise SystemExit("Debe indicar un código o una clave general. No se ha eliminado la instalación anterior.")
if any(ord(c) < 32 or ord(c) == 127 for c in key):
    raise SystemExit("La clave no admite caracteres de control. No se ha eliminado la instalación anterior.")
'
}

prepare_runtime_archive() {
  printf 'Descargando Python 3.12.16 aislado antes de eliminar la instalación anterior.\n'
  curl --fail --location --proto '=https' --proto-redir '=https' \
    --retry 2 --connect-timeout 15 --max-time 300 \
    --output "$WORK_DIR/python.tar.gz.part" "$RUNTIME_URL" || return 1
  printf '%s  %s\n' "$RUNTIME_SHA256" "$WORK_DIR/python.tar.gz.part" | sha256sum -c - || return 1
  install -d -m 0700 "$WORK_DIR/runtime" || return 1
  tar -xzf "$WORK_DIR/python.tar.gz.part" --no-same-owner -C "$WORK_DIR/runtime" || return 1
  [[ -f "$WORK_DIR/runtime/python/bin/python3.12" ]] || fail "El runtime descargado está incompleto."
}

reset_existing_installation() {
  validate_reset_paths || return 1
  check_execution_mount || return 1
  local load
  if ! load="$(systemctl show telemetry-agent.service -p LoadState --value)"; then
    [[ "$load" == not-found ]] \
      || { fail "No se pudo consultar el servicio; no se borra la instalación."; return 1; }
  fi
  [[ -n "$load" ]] || { fail "El servicio devolvió un estado vacío; no se borra la instalación."; return 1; }
  if [[ "$load" != not-found ]]; then
    systemctl stop telemetry-agent.service \
      || { fail "No se pudo detener el servicio; no se borra la instalación."; return 1; }
    systemctl disable telemetry-agent.service \
      || { fail "No se pudo deshabilitar el servicio; no se borra la instalación."; return 1; }
    systemctl reset-failed telemetry-agent.service || true
  fi
  printf 'Eliminando programa, runtime, configuración e identidad anteriores.\n'
  rm -f -- "$WANTS_FILE" || return 1
  rm -rf --one-file-system -- "$INSTALL_DIR" "${CONFIG_FILE%/*}" "${IDENTITY_FILE%/*}" "$UNIT_FILE" "$UNIT_FILE.d" || return 1
  systemctl daemon-reload || return 1
  printf 'Limpieza local completada. Se creará una identidad nueva; la ficha anterior del panel permanece.\n'
}

normalize_runtime_permissions() {
  local runtime="$1" executable
  [[ -d "$runtime" && ! -L "$runtime" ]] || { fail "El runtime no es un directorio válido."; return 1; }
  executable="$(readlink -f -- "$runtime/bin/python3")" || return 1
  [[ "$executable" == "$runtime/"* && -f "$executable" ]] \
    || { fail "El ejecutable de Python no pertenece al runtime preparado."; return 1; }
  chown -R root:root "$runtime" || return 1
  find "$runtime" -type d -exec chmod 0755 -- {} + || return 1
  find "$runtime" -type f -exec chmod u=rwX,go=rX -- {} + || return 1
  chmod 0755 -- "$executable"
}

install_prepared_runtime() {
  install -d -o root -g root -m 0755 "$INSTALL_DIR" || return 1
  mv -- "$WORK_DIR/runtime/python" "$RUNTIME_DIR" || return 1
  normalize_runtime_permissions "$RUNTIME_DIR" || return 1
  PYTHON_BIN="$RUNTIME_DIR/bin/python3"
  "$PYTHON_BIN" -I -c 'import sys,ssl,venv,ensurepip; print("Python aislado: " + sys.version.split()[0]); print(ssl.OPENSSL_VERSION)'
}

install_agent() {
  local installer="$WORK_DIR/inventario-agente-$AGENT_VERSION/scripts/install-linux.sh"
  local rc=0
  # El código se ve por el eco de la terminal. Se entrega al instalador por
  # stdin, sin guardarlo en argumentos, archivos temporales ni la bitácora.
  if printf '%s\n%s\n' "$INSTALLATION_CODE_VALUE" "$ENROLLMENT_KEY_VALUE" \
      | env PATH="$(dirname -- "$PYTHON_BIN"):$SYSTEM_PATH" /bin/bash "$installer" --server-url "$SERVER_URL"; then
    rc=0
  else
    rc=$?
  fi
  unset INSTALLATION_CODE_VALUE ENROLLMENT_KEY_VALUE
  return "$rc"
}

diagnose_service() {
  local executable
  printf '\n--- Diagnóstico de telemetry-agent.service ---\n'
  systemctl show telemetry-agent.service --no-pager \
    -p LoadState -p ActiveState -p SubState -p Result -p MainPID \
    -p ExecMainCode -p ExecMainStatus -p NRestarts -p User -p Group \
    -p WorkingDirectory -p ExecStart -p ActiveEnterTimestamp -p StateChangeTimestamp || true
  systemctl status telemetry-agent.service --no-pager --full || true
  if command -v namei >/dev/null; then
    namei -l "$INSTALL_DIR/venv/bin/python" || true
  fi
  if executable="$(readlink -f -- "$INSTALL_DIR/venv/bin/python")" && [[ -n "$executable" ]]; then
    findmnt -n -T "$executable" -o TARGET,OPTIONS || true
  fi
  journalctl -u telemetry-agent.service -n 40 --no-pager || true
  printf '%s\n' '--- Fin del diagnóstico ---'
}

wait_for_service_active() {
  local timeout="${1:-60}" elapsed=0 snapshot key value
  local load state substate result pid restarts exit_status initial_restarts=""
  local stable=0 previous_pid="" previous_restarts="" previous_status="" status_line
  while ((elapsed <= timeout)); do
    if ! snapshot="$(systemctl show telemetry-agent.service --no-pager \
        -p LoadState -p ActiveState -p SubState -p Result -p MainPID \
        -p ExecMainStatus -p NRestarts 2>/dev/null)"; then
      printf '\nERROR: no se pudo consultar el estado del servicio.\n' >&2
      diagnose_service
      return 1
    fi
    load="" state="" substate="" result="" pid=0 restarts=0 exit_status=""
    while IFS='=' read -r key value; do
      case "$key" in
        LoadState) load="$value" ;;
        ActiveState) state="$value" ;;
        SubState) substate="$value" ;;
        Result) result="$value" ;;
        MainPID) pid="$value" ;;
        ExecMainStatus) exit_status="$value" ;;
        NRestarts) restarts="$value" ;;
      esac
    done <<< "$snapshot"
    [[ "$pid" =~ ^[0-9]+$ ]] || pid=0
    [[ "$restarts" =~ ^[0-9]+$ ]] || restarts=0
    if [[ -z "$initial_restarts" ]]; then initial_restarts="$restarts"; fi
    status_line="Estado: ${state:-desconocido}/${substate:-desconocido}; PID=$pid; reinicios=$restarts; salida=${exit_status:-desconocida}; resultado=${result:-desconocido}"
    if [[ "$status_line" != "$previous_status" ]]; then
      printf '%s\n' "$status_line"
      previous_status="$status_line"
    fi
    if [[ "$load" != loaded || "$state" == failed || "$state" == inactive || "$state" == deactivating ]]; then
      printf '\nERROR: el servicio no está arrancando correctamente.\n' >&2
      diagnose_service
      return 1
    fi
    if [[ "$state" == active && "$substate" == running ]] && ((pid > 0)); then
      if [[ "$pid" == "$previous_pid" && "$restarts" == "$previous_restarts" ]]; then
        stable=$((stable + 1))
      else
        stable=1
      fi
      previous_pid="$pid" previous_restarts="$restarts"
      if ((stable >= 3)); then
        printf 'Servicio activo y estable en tres comprobaciones consecutivas.\n'
        return 0
      fi
    else
      stable=0 previous_pid="" previous_restarts=""
    fi
    if ((restarts - initial_restarts >= 2)); then
      printf '\nERROR: el agente vuelve a fallar y systemd lo reinicia automáticamente.\n' >&2
      diagnose_service
      return 1
    fi
    if ((elapsed >= timeout)); then break; fi
    sleep 2
    elapsed=$((elapsed + 2))
  done
  printf '\nERROR: no se confirmó un servicio estable en %s segundos.\n' "$timeout" >&2
  diagnose_service
  return 1
}

verify_installed_agent() {
  step '6. Verificar servicio, dependencias y conexión'
  wait_for_service_active || return 1
  if ! systemctl is-enabled telemetry-agent.service; then
    printf '\nERROR: el servicio no está habilitado para el arranque.\n' >&2
    diagnose_service
    return 1
  fi
  if ! runuser -u telemetry-agent -- "$INSTALL_DIR/venv/bin/python" -I -c \
      'import sys,ssl,psutil,telemetry_agent; print("Python agente: " + sys.version.split()[0]); print("Ejecutable: " + sys.executable); print("Intérprete base: " + str(getattr(sys,"_base_executable",sys.executable))); print("Base: " + sys.base_prefix); print("Agente: " + telemetry_agent.__version__); print("psutil: " + psutil.__version__)'; then
    printf '\nERROR: no se pudo ejecutar el Python del agente como usuario telemetry-agent.\n' >&2
    diagnose_service
    return 1
  fi
  if ! runuser -u telemetry-agent -- "$INSTALL_DIR/venv/bin/python" -I -m telemetry_agent --config "$CONFIG_FILE" --check-connection; then
    printf '\nERROR: falló la comprobación de conexión del agente.\n' >&2
    diagnose_service
    return 1
  fi
  stat -c '%a %U %G %n' "$CONFIG_FILE"
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

finish_verification() {
  step '7. Confirmar inscripción e indicar la aprobación'
  check_registration
  stat -c '%a %U %G %n' "$IDENTITY_FILE"
  printf '\nPanel: %s\nEquipo: %s\n' "$PANEL_URL" "$(hostname)"
  printf 'Abra Solicitudes, revise la ubicación y apruebe este equipo si está pendiente. Después revise que aparezca En línea.\n'
  printf 'Estado del servicio: sudo systemctl status telemetry-agent.service --no-pager\n'
  printf 'Registro del agente: sudo journalctl -u telemetry-agent.service -n 40 --no-pager\n'
  printf 'Bitácora de esta verificación: %s\n' "$LOG_FILE"
  printf 'El servicio se inicia con el sistema. No se necesita reiniciar el equipo.\n'
}

main() {
  local verify_only=0
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
    --verify)
      (($# == 1)) || { usage >&2; return 2; }
      verify_only=1 ;;
    "") ;;
    *) usage >&2; return 2 ;;
  esac
  if ((verify_only == 0 && $# != 0)); then usage >&2; return 2; fi
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
  if ((verify_only)); then
    if [[ ! -f "$CONFIG_FILE" || ( ! -e "$INSTALL_DIR/venv/bin/python" && ! -L "$INSTALL_DIR/venv/bin/python" ) ]]; then
      diagnose_service
      fail "No se encontró una instalación completa que verificar."
    fi
    command -v python3 >/dev/null || fail "Se requiere python3 para leer la configuración existente."
    check_existing_installation
    verify_installed_agent
    finish_verification
    return 0
  fi
  ensure_dependencies
  [[ "$(df -Pk /opt | awk 'NR==2 {print $4}')" -ge 524288 ]] || fail "Se requieren al menos 512 MiB libres en /opt."
  validate_reset_paths
  check_execution_mount

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

  step '4. Preparar código y runtime antes de la limpieza'
  collect_installation_credentials
  prepare_runtime_archive

  step '5. Eliminar la instalación anterior e instalar desde cero'
  reset_existing_installation
  install_prepared_runtime
  install_agent
  printf 'INSTALL_EXIT=0\n'

  verify_installed_agent
  finish_verification
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
  exit 0
fi
return 0

__INVENTARIO_AGENT_ZIP_BASE64__
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
tOzYAkPB5HxE6Zk3mxi0pY9CY2zH6WK74e0oXfdMIAa21tlbknnuiGRABjvbecJuUFtC28bLtP8R
LdYSDta9IWDDnUcjs9u1VcmXVzLm7bVuW/WRyCTKKmngemxn0iqzsZtpd+evCms9g5XvF/4DUEsD
BBQAAAAIAAAAIQAf89NDUAAAAFUAAAAzAAAAaW52ZW50YXJpby1hZ2VudGUtMC4zLjEvdGVsZW1l
dHJ5X2FnZW50L19faW5pdF9fLnB5FchBCoAgEAXQvacY5gBStO4AnUJMfjQwaukkdPvoLR8zb6Vb
VI27gpIKitFRG9kJwv3Ilf8xKDKsvdTRhiR4ZnYuhIHWpZYQaCWe/OJndh9QSwMEFAAAAAgAAAAh
AGLx23w3CAAA3xkAADMAAABpbnZlbnRhcmlvLWFnZW50ZS0wLjMuMS90ZWxlbWV0cnlfYWdlbnQv
X19tYWluX18ucHmlWNuO2zYavvdTcLUIIKO2ML2dwAWCYLrNIpsGzWALNBgoHIm2mVCkSlLOONk8
zF7uRa/yCPNi/X+edPIcsvXFjCT+/M+Hj8yy7JdOko/c7sm7d+3R7pUk64ZYJljDrD6WdMekJet1
peSW74h7Ld4bJd+9K7IsWyy2WjWkLLed7TQrS8KbVmlLqJTKUsuVNItF/KZ3LdWG+T01tbQS1Bhm
4ibNWkGrfp1Z3rC4GN9XBP9+UpJFvqhOfBZqt+Ny51m01O4Fv44cXsNrpDN8J6mIb3avGa1xn984
tT+QleWBaQM2leVJuqISfEB+GVef4eIdO7xfww5HeKG10ivy3K2syIsavnF7XJGPmltWshvatIKd
Zmc1lcaxChyrPas+lCBFsgqjsVgsarYlDeUyh3gczongxr41Vl+R/5BX4FWycf+WZP0D4dKeLwj8
XNw0LMUYFs/0rmtA5Gu3ktfMVJq3KGKTOTMYqVnS7/YPiq/s9463ypBfuazVR0OO5CWX3U2RLQdS
ClrXJQ3s82y9Dk7PVoRWXkD/JTxtBqHxvIzqdIXGDJg2kKRUiCP4sBKd4QdW7rTq2lyjYprVm0vd
seH+mS4+XiDYHlu2wYxakT0TLRitqz0/KPLPNz+/Qls9ZadpxW+/ymjiHWy55PYkb3AePVC9yV4/
u/wpi7KeQ7pq0kk6keJ8/J5BfijSan6gNX3At0pWbOBYYxVUsQUvJFkX71nVWSeOVLwCzkey5VA8
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
se8itJjfW/5/SV70GwacQ0ACQAzId6QLOx4LXTDcefIKFP6eQpBBNXTLWzjpfxv4MBjYcIMCwqFp
TIlWhulQmEZ2pamuFPnXlHz1/Hm97eKq/p7kW4KhCSizDbMHuCnxUcCgHqpWZcWG78tKoGEBCOh7
wtwUn03dPh6y76G5by4fulusfiM7GjIfkgTuTx8Qgh5NMzOaHN9PFNcDwxbyIUbtJ4MeK9/1Pu47
leV8vrTPwYgztMc4H7S+hLch6dIwDu0A4PpLWyVBHghrzK/Q9FfBAPPRurQfZyDsUCQsmqQ3Q/SV
fEvzijkVzwXHXVH3G8c/DZmavJvpQzIcC5sR4BMYDdT4L1BLAQIUAxQAAAAIAAAAIQCB3cpaLAAA
ACwAAAAiAAAAAAAAAAAAAACkgQAAAABpbnZlbnRhcmlvLWFnZW50ZS0wLjMuMS8uZ2l0aWdub3Jl
UEsBAhQDFAAAAAgAAAAhALqnqEmuAgAAlQQAACcAAAAAAAAAAAAAAKSBbAAAAGludmVudGFyaW8t
YWdlbnRlLTAuMy4xL01BTklGRVNULnNoYTI1NlBLAQIUAxQAAAAIAAAAIQDUOKzZng0AAIkiAAAh
AAAAAAAAAAAAAACkgV8DAABpbnZlbnRhcmlvLWFnZW50ZS0wLjMuMS9SRUFETUUubWRQSwECFAMU
AAAACAAAACEA0RPpDwoBAACTAQAAMQAAAAAAAAAAAAAApIE8EQAAaW52ZW50YXJpby1hZ2VudGUt
MC4zLjEvYWdlbnQtY29uZmlnLmV4YW1wbGUuanNvblBLAQIUAxQAAAAIAAAAIQBb+3zY8wAAAH8B
AAAmAAAAAAAAAAAAAACkgZUSAABpbnZlbnRhcmlvLWFnZW50ZS0wLjMuMS9weXByb2plY3QudG9t
bFBLAQIUAxQAAAAIAAAAIQCQkfrZyAsAAMwbAAAwAAAAAAAAAAAAAADtgcwTAABpbnZlbnRhcmlv
LWFnZW50ZS0wLjMuMS9zY3JpcHRzL2luc3RhbGwtbGludXguc2hQSwECFAMUAAAACAAAACEAeJ+2
E/wKAABdIAAAMwAAAAAAAAAAAAAApIHiHwAAaW52ZW50YXJpby1hZ2VudGUtMC4zLjEvc2NyaXB0
cy9pbnN0YWxsLXdpbmRvd3MucHMxUEsBAhQDFAAAAAgAAAAhAB/z00NQAAAAVQAAADMAAAAAAAAA
AAAAAKSBLysAAGludmVudGFyaW8tYWdlbnRlLTAuMy4xL3RlbGVtZXRyeV9hZ2VudC9fX2luaXRf
Xy5weVBLAQIUAxQAAAAIAAAAIQBi8dt8NwgAAN8ZAAAzAAAAAAAAAAAAAACkgdArAABpbnZlbnRh
cmlvLWFnZW50ZS0wLjMuMS90ZWxlbWV0cnlfYWdlbnQvX19tYWluX18ucHlQSwECFAMUAAAACAAA
ACEA9dqud0oKAACPIwAAMQAAAAAAAAAAAAAApIFYNAAAaW52ZW50YXJpby1hZ2VudGUtMC4zLjEv
dGVsZW1ldHJ5X2FnZW50L2NsaWVudC5weVBLAQIUAxQAAAAIAAAAIQCjA6y+AAsAAIIiAAA0AAAA
AAAAAAAAAACkgfE+AABpbnZlbnRhcmlvLWFnZW50ZS0wLjMuMS90ZWxlbWV0cnlfYWdlbnQvY29s
bGVjdG9yLnB5UEsBAhQDFAAAAAgAAAAhAPQRdNP/DAAAay0AADEAAAAAAAAAAAAAAKSBQ0oAAGlu
dmVudGFyaW8tYWdlbnRlLTAuMy4xL3RlbGVtZXRyeV9hZ2VudC9jb25maWcucHlQSwECFAMUAAAA
CAAAACEASdaZbeYbAAAaYQAAOQAAAAAAAAAAAAAApIGRVwAAaW52ZW50YXJpby1hZ2VudGUtMC4z
LjEvdGVsZW1ldHJ5X2FnZW50L3JlbW90ZV9jb250cm9sLnB5UEsBAhQDFAAAAAgAAAAhADtRVCyW
CQAAkR0AADQAAAAAAAAAAAAAAKSBznMAAGludmVudGFyaW8tYWdlbnRlLTAuMy4xL3RlbGVtZXRy
eV9hZ2VudC90cmFuc3BvcnQucHlQSwUGAAAAAA4ADgARBQAAtn0AAAAA
