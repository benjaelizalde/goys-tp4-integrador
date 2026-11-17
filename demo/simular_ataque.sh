#!/bin/bash
# ==============================================================================
# Script de Demostración en Vivo para la Feria de Redes (UTN FRLP GOYS)
# Simulación de Tráfico Legítimo, Ataques Web y Verificación de Remediación
# ==============================================================================

# Colores de salida
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

VICTIM_URL="http://172.28.0.10"
HOST_URL="http://localhost:8080"
ATTACKER_CONTAINER="demo_attacker"

# Asegura que el kernel pase el tráfico del bridge br-monitored por iptables FORWARD/DOCKER-USER
ensure_bridge_netfilter() {
    if [ ! -f /proc/sys/net/bridge/bridge-nf-call-iptables ]; then
        sudo modprobe br_netfilter 2>/dev/null || true
    fi
    if [ -f /proc/sys/net/bridge/bridge-nf-call-iptables ]; then
        if [ "$(cat /proc/sys/net/bridge/bridge-nf-call-iptables)" != "1" ]; then
            sudo sysctl -w net.bridge.bridge-nf-call-iptables=1 >/dev/null 2>&1 || true
        fi
    else
        echo -e "${RED}⚠️  No se pudo habilitar br_netfilter (net.bridge.bridge-nf-call-iptables).${NC}"
        echo -e "${YELLOW}   Ejecutá: sudo modprobe br_netfilter && sudo sysctl -w net.bridge.bridge-nf-call-iptables=1${NC}"
        sleep 2
    fi
}

# Función para verificar si el contenedor atacante está activo
check_attacker_container() {
    if docker ps --format '{{.Names}}' | grep -q "^${ATTACKER_CONTAINER}$"; then
        return 0
    else
        return 1
    fi
}

# Ejecutar comando HTTP desde el contenedor atacante (IP 172.28.0.99) o desde host
exec_curl() {
    local endpoint="$1"
    local extra_args="$2"
    if check_attacker_container; then
        docker exec -t "$ATTACKER_CONTAINER" curl -s -m 3 $extra_args "${VICTIM_URL}${endpoint}"
    else
        curl -s -m 3 $extra_args "${HOST_URL}${endpoint}"
    fi
}

exec_curl_status() {
    local endpoint="$1"
    local extra_args="$2"
    if check_attacker_container; then
        docker exec -t "$ATTACKER_CONTAINER" curl -s -m 3 -o /dev/null -w "%{http_code}" $extra_args "${VICTIM_URL}${endpoint}"
    else
        curl -s -m 3 -o /dev/null -w "%{http_code}" $extra_args "${HOST_URL}${endpoint}"
    fi
}

# Verifica que el atacante no esté ya bloqueado antes de lanzar un ataque nuevo
ensure_attacker_unblocked() {
    local pre_status
    pre_status=$(exec_curl_status "/")
    if [ "$pre_status" != "200" ]; then
        echo -e "  ${YELLOW}⚠️  La IP del atacante ya está bloqueada en firewall (HTTP ${pre_status}) — no se envía el ataque.${NC}"
        echo -e "  ${CYAN}ℹ️  Ejecutá la opción 7 (Resetear Reglas de Firewall) antes de probar otro ataque.${NC}"
        echo ""
        return 1
    fi
    return 0
}

banner() {
    clear
    echo -e "${CYAN}======================================================================${NC}"
    echo -e "${CYAN}        DEMO INTERACTIVA: SOC/NOC AUTÓNOMO CON GROQ LLM           ${NC}"
    echo -e "${CYAN}              Feria de Redes — UTN FRLP (GOYS TP4)                   ${NC}"
    echo -e "${CYAN}======================================================================${NC}"
    echo ""
}

test_legitimate() {
    echo -e "${BLUE}▶ [1/3] Enviando tráfico legítimo al servidor web...${NC}"
    for i in {1..5}; do
        STATUS=$(exec_curl_status "/")
        if [ "$STATUS" == "200" ]; then
            echo -e "  Petición $i: ${GREEN}HTTP 200 OK${NC} (Servicio saludable)"
        else
            echo -e "  Petición $i: ${RED}HTTP $STATUS (Degradado o bloqueado)${NC}"
        fi
        sleep 0.5
    done
    echo ""
}

test_sqli() {
    ensure_attacker_unblocked || return
    echo -e "${YELLOW}▶ [2/3] Inyectando Vector Malicioso: Inyección SQL (SQLi)...${NC}"
    echo -e "  Payload: ${CYAN}/?id=1%20UNION%20SELECT%20null,username,password%20FROM%20users${NC}"
    
    exec_curl "/?id=1%20UNION%20SELECT%20null,username,password%20FROM%20users" > /dev/null 2>&1
    echo -e "  ${YELLOW}⚠️  Ataque enviado al sensor Suricata IDS.${NC}"
    echo -e "  Esperando análisis del Agente Groq LLM y aplicación de regla iptables..."
    
    BLOCKED=false
    for attempt in {1..8}; do
        sleep 0.8
        STATUS=$(exec_curl_status "/")
        if [ "$STATUS" != "200" ]; then
            BLOCKED=true
            break
        fi
    done

    echo ""
    echo -e "${BLUE}▶ [3/3] Verificando estado del atacante (Remediación Activa)...${NC}"
    if [ "$BLOCKED" = true ]; then
        echo -e "  ${GREEN}✅ ÉXITO TOTAL: IP del atacante BLOQUEADA en firewall (Drop/Timeout).${NC}"
    else
        echo -e "  ${RED}❌ FALLO DE MITIGACIÓN: El atacante todavía puede acceder al servidor (HTTP $STATUS).${NC}"
    fi
    echo ""
}

test_recon() {
    ensure_attacker_unblocked || return
    echo -e "${YELLOW}▶ [Ataque Reconocimiento] Escáner automatizado con User-Agent sospechoso (sqlmap)...${NC}"
    exec_curl "/" "-A 'sqlmap/1.8.2#stable'" > /dev/null 2>&1
    echo -e "  Ataque enviado con User-Agent 'sqlmap'. Esperando remediación..."
    
    BLOCKED=false
    for attempt in {1..8}; do
        sleep 0.8
        STATUS=$(exec_curl_status "/")
        if [ "$STATUS" != "200" ]; then
            BLOCKED=true
            break
        fi
    done

    if [ "$BLOCKED" = true ]; then
        echo -e "  ${GREEN}✅ ÉXITO: Escáner neutralizado y bloqueado en firewall.${NC}"
    else
        echo -e "  ${RED}❌ FALLO: No se bloqueó el escáner (HTTP $STATUS).${NC}"
    fi
    echo ""
}

test_path_traversal() {
    ensure_attacker_unblocked || return
    echo -e "${YELLOW}▶ [Ataque LFI] Intento de acceso a archivo del sistema (/etc/passwd)...${NC}"
    exec_curl "/admin/view?file=/etc/passwd" > /dev/null 2>&1
    echo -e "  Payload enviado. Esperando dictamen de la IA..."
    
    BLOCKED=false
    for attempt in {1..8}; do
        sleep 0.8
        STATUS=$(exec_curl_status "/")
        if [ "$STATUS" != "200" ]; then
            BLOCKED=true
            break
        fi
    done

    if [ "$BLOCKED" = true ]; then
        echo -e "  ${GREEN}✅ ÉXITO: Atacante bloqueado por intento de acceso indebido.${NC}"
    else
        echo -e "  ${RED}❌ FALLO: No se bloqueó el path traversal (HTTP $STATUS).${NC}"
    fi
    echo ""
}

check_telemetry() {
    echo -e "${CYAN}▶ Consultando Telemetría del Agente AIOps (http://localhost:8000/status)...${NC}"
    if curl -s -m 2 http://localhost:8000/status > /dev/null; then
        curl -s http://localhost:8000/status
    else
        echo -e "${RED}El agente no tiene el servidor de telemetría activo en el puerto 8000.${NC}"
    fi
    echo ""
}

reset_firewall() {
    echo -e "${YELLOW}▶ Reseteando reglas de filtrado en FORWARD y DOCKER-USER...${NC}"
    for ip in 172.28.0.97 172.28.0.98 172.28.0.99; do
        while sudo iptables -D FORWARD -s "$ip" -j DROP 2>/dev/null; do :; done
        while sudo iptables -D DOCKER-USER -s "$ip" -j DROP 2>/dev/null; do :; done
    done
    curl -s http://localhost:8000/reset > /dev/null 2>&1
    echo -e "${GREEN}✅ Firewall y telemetría reseteados. Todas las IPs pueden acceder nuevamente.${NC}"
    echo ""
}

test_multi_ip_attack() {
    ensure_attacker_unblocked || return
    echo -e "${YELLOW}▶ [Ataque Multi-IP / Botnet Simulada] Lanzando SQLi desde 3 IPs distintas (.99, .98, .97)...${NC}"

    local payload="/?id=1%20UNION%20SELECT%20null,username,password%20FROM%20users"
    exec_curl "$payload" > /dev/null 2>&1 &
    for ip in 172.28.0.98 172.28.0.97; do
        docker run --rm --network br-monitored --ip "$ip" alpine/curl:latest \
            curl -s -m 3 "${VICTIM_URL}${payload}" > /dev/null 2>&1 &
    done
    wait

    echo -e "  ${YELLOW}⚠️  Ataques enviados desde 3 orígenes. Esperando análisis IA y bloqueo...${NC}"
    for attempt in {1..10}; do
        sleep 0.8
        local count
        count=$(curl -s -m 2 http://localhost:8000/status | grep -o '"blocked_ips_count": [0-9]*' | awk '{print $2}')
        if [ -n "$count" ] && [ "$count" -ge 3 ]; then
            break
        fi
    done

    local leg_status
    leg_status=$(curl -s -m 2 -o /dev/null -w "%{http_code}" "${HOST_URL}/")
    echo -e "  ${GREEN}✅ Tráfico legítimo (${HOST_URL}): HTTP ${leg_status}${NC}"
    check_telemetry
}

# Menú interactivo
ensure_bridge_netfilter
while true; do
    banner
    echo "Seleccione una opción para la demo:"
    echo "  1) Enviar tráfico legítimo (Línea base NOC)"
    echo "  2) Simular Ataque SQL Injection (Demo Principal para la Feria)"
    echo "  3) Simular Escáner Automatizado (User-Agent sqlmap)"
    echo "  4) Simular Path Traversal (/etc/passwd)"
    echo "  5) Ver Telemetría e Incidentes en vivo (API Agente)"
    echo "  6) Ejecutar Demo Completa Automatizada (1 -> 2 -> Verificación)"
    echo "  7) Resetear Reglas de Firewall (Desbloquear IPs)"
    echo "  8) Simular Ataque Multi-IP / Botnet (3 IPs: .99, .98, .97)"
    echo "  0) Salir"
    echo ""
    read -p "Opción [0-8]: " opcion

    case $opcion in
        1)
            test_legitimate
            read -p "Presione ENTER para continuar..."
            ;;
        2)
            test_sqli
            read -p "Presione ENTER para continuar..."
            ;;
        3)
            test_recon
            read -p "Presione ENTER para continuar..."
            ;;
        4)
            test_path_traversal
            read -p "Presione ENTER para continuar..."
            ;;
        5)
            check_telemetry
            read -p "Presione ENTER para continuar..."
            ;;
        6)
            test_legitimate
            sleep 1
            test_sqli
            sleep 1
            check_telemetry
            read -p "Presione ENTER para continuar..."
            ;;
        7)
            reset_firewall
            read -p "Presione ENTER para continuar..."
            ;;
        8)
            test_multi_ip_attack
            read -p "Presione ENTER para continuar..."
            ;;
        0)
            echo "Saliendo de la demo."
            exit 0
            ;;
        *)
            echo -e "${RED}Opción inválida.${NC}"
            sleep 1
            ;;
    esac
done
