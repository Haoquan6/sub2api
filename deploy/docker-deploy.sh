#!/usr/bin/env bash
# =============================================================================
# PixelHub Docker Deployment Helper
# =============================================================================
# From a cloned PixelHub repository:
#   bash deploy/docker-deploy.sh --start
#
# What it does:
#   - prepares deploy/.env with generated secrets
#   - creates local data directories
#   - optionally starts Docker Compose with --build
# =============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

START=false
YES=false

while [ $# -gt 0 ]; do
    case "$1" in
        --start)
            START=true
            ;;
        -y|--yes)
            YES=true
            ;;
        -h|--help)
            echo "Usage: bash deploy/docker-deploy.sh [--start] [-y]"
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
    shift
done

print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

generate_secret() {
    if command_exists openssl; then
        openssl rand -hex 32
    else
        local secret=""
        while [ "${#secret}" -lt 64 ]; do
            secret="${secret}$(od -An -N32 -tx1 /dev/urandom | tr -d ' \n')"
        done
        printf '%s\n' "${secret:0:64}"
    fi
}

compose_cmd() {
    if docker compose version >/dev/null 2>&1; then
        docker compose "$@"
    elif command_exists docker-compose; then
        docker-compose "$@"
    else
        print_error "Docker Compose is not available. Install Docker Compose v2 first."
        exit 1
    fi
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
cd "${script_dir}"

echo ""
echo "=========================================="
echo "  PixelHub Docker Deployment"
echo "=========================================="
echo ""

if ! command_exists docker; then
    print_error "docker is not installed or not in PATH."
    exit 1
fi

if [ ! -f "${repo_root}/Dockerfile" ] || [ ! -d "${repo_root}/frontend" ] || [ ! -d "${repo_root}/backend" ]; then
    print_error "This helper must run from a cloned PixelHub repository."
    print_info "Expected repository layout: Dockerfile, frontend/, backend/, deploy/"
    exit 1
fi

if [ -f ".env" ] && [ "${YES}" != "true" ]; then
    print_warning "deploy/.env already exists."
    read -r -p "Keep existing .env and only create missing directories? (Y/n): " reply
    if [[ "${reply}" =~ ^[Nn]$ ]]; then
        mv .env ".env.backup.$(date +%Y%m%d%H%M%S)"
        print_info "Existing .env was backed up."
    fi
fi

if [ ! -f ".env" ]; then
    print_info "Generating deploy/.env from .env.example..."
    cp .env.example .env

    jwt_secret="$(generate_secret)"
    totp_key="$(generate_secret)"
    postgres_password="$(generate_secret)"
    admin_password="$(generate_secret | head -c 20)"

    if sed --version >/dev/null 2>&1; then
        sed -i "s/^JWT_SECRET=.*/JWT_SECRET=${jwt_secret}/" .env
        sed -i "s/^TOTP_ENCRYPTION_KEY=.*/TOTP_ENCRYPTION_KEY=${totp_key}/" .env
        sed -i "s/^POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=${postgres_password}/" .env
        sed -i "s/^ADMIN_PASSWORD=.*/ADMIN_PASSWORD=${admin_password}/" .env
    else
        sed -i '' "s/^JWT_SECRET=.*/JWT_SECRET=${jwt_secret}/" .env
        sed -i '' "s/^TOTP_ENCRYPTION_KEY=.*/TOTP_ENCRYPTION_KEY=${totp_key}/" .env
        sed -i '' "s/^POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=${postgres_password}/" .env
        sed -i '' "s/^ADMIN_PASSWORD=.*/ADMIN_PASSWORD=${admin_password}/" .env
    fi

    chmod 600 .env || true
    print_success "Generated deploy/.env"
else
    print_info "Using existing deploy/.env"
fi

print_info "Creating data directories..."
mkdir -p data postgres_data redis_data
print_success "Data directories are ready"

echo ""
echo "Generated or configured admin account:"
grep -E '^(ADMIN_EMAIL|ADMIN_PASSWORD)=' .env | sed 's/^/  /'
echo ""
print_warning "Keep deploy/.env private. It contains database and signing secrets."

if [ "${START}" = "true" ]; then
    print_info "Starting PixelHub with Docker Compose..."
    compose_cmd -f docker-compose.local.yml up -d --build
    print_success "PixelHub is starting."
    echo ""
    echo "Useful commands:"
    echo "  cd deploy"
    echo "  docker compose -f docker-compose.local.yml ps"
    echo "  docker compose -f docker-compose.local.yml logs -f pixelhub"
    echo ""
    echo "Open:"
    echo "  http://localhost:${SERVER_PORT:-$(grep -E '^SERVER_PORT=' .env | cut -d= -f2 || echo 8080)}"
else
    print_success "Preparation complete."
    echo ""
    echo "Start services:"
    echo "  cd deploy"
    echo "  docker compose -f docker-compose.local.yml up -d --build"
    echo ""
    echo "View logs:"
    echo "  docker compose -f docker-compose.local.yml logs -f pixelhub"
fi
