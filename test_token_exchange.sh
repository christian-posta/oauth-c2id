#!/bin/bash

# Token Exchange Test Script for Connect2ID
# Demonstrates the OAuth 2.0 token exchange flow

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${PURPLE}[STEP]${NC} $1"; }
log_token() { echo -e "${CYAN}[TOKEN]${NC} $1"; }

# Configuration
SERVER_URL="http://localhost:8080/c2id"
USERNAME="alice"
PASSWORD="secret"

# Load client credentials
if [ ! -f .subject_client_id ] || [ ! -f .subject_client_secret ] || [ ! -f .actor_client_id ] || [ ! -f .actor_client_secret ]; then
    log_error "Client credentials not found. Please run setup_token_exchange.sh first."
    exit 1
fi

SUBJECT_CLIENT_ID=$(cat .subject_client_id)
SUBJECT_CLIENT_SECRET=$(cat .subject_client_secret)
ACTOR_CLIENT_ID=$(cat .actor_client_id)
ACTOR_CLIENT_SECRET=$(cat .actor_client_secret)

# Get subject token directly using password grant
get_subject_token() {
    log_step "Getting subject token using password grant..."
    
    RESPONSE=$(curl -s -w "\n%{http_code}" \
        -X POST "$SERVER_URL/token" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -H "Authorization: Basic $(echo -n "$SUBJECT_CLIENT_ID:$SUBJECT_CLIENT_SECRET" | base64)" \
        -d "grant_type=password&username=$USERNAME&password=$PASSWORD&scope=openid%20profile%20email")
    
    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    RESPONSE_BODY=$(echo "$RESPONSE" | sed '$d')
    
    if [ "$HTTP_CODE" = "200" ]; then
        SUBJECT_TOKEN=$(echo "$RESPONSE_BODY" | jq -r '.access_token')
        echo "$SUBJECT_TOKEN" > .subject_token
        log_success "Subject token obtained"
        log_token "Subject token: ${SUBJECT_TOKEN:0:20}..."
        
        # Display token claims
        log_info "Subject token claims:"
        echo "$SUBJECT_TOKEN" | cut -d'.' -f2 | base64 -d 2>/dev/null | jq . 2>/dev/null || echo "Unable to decode token"
    else
        log_error "Failed to get subject token"
        echo "$RESPONSE_BODY" | jq . 2>/dev/null || echo "$RESPONSE_BODY"
        exit 1
    fi
}

# Get actor token
get_actor_token() {
    log_step "Getting actor token..."
    
    RESPONSE=$(curl -s -w "\n%{http_code}" \
        -X POST "$SERVER_URL/token" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -H "Authorization: Basic $(echo -n "$ACTOR_CLIENT_ID:$ACTOR_CLIENT_SECRET" | base64)" \
        -d "grant_type=client_credentials&scope=token_exchange")
    
    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    RESPONSE_BODY=$(echo "$RESPONSE" | sed '$d')
    
    if [ "$HTTP_CODE" = "200" ]; then
        ACTOR_TOKEN=$(echo "$RESPONSE_BODY" | jq -r '.access_token')
        echo "$ACTOR_TOKEN" > .actor_token
        log_success "Actor token obtained"
        log_token "Actor token: ${ACTOR_TOKEN:0:20}..."
        
        # Display token claims
        log_info "Actor token claims:"
        echo "$ACTOR_TOKEN" | cut -d'.' -f2 | base64 -d 2>/dev/null | jq . 2>/dev/null || echo "Unable to decode token"
    else
        log_error "Failed to get actor token"
        echo "$RESPONSE_BODY" | jq . 2>/dev/null || echo "$RESPONSE_BODY"
        exit 1
    fi
}

# Perform token exchange
exchange_token() {
    log_step "Performing token exchange..."
    
    SUBJECT_TOKEN=$(cat .subject_token)
    ACTOR_TOKEN=$(cat .actor_token)
    
    RESPONSE=$(curl -s -w "\n%{http_code}" \
        -X POST "$SERVER_URL/token" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -H "Authorization: Basic $(echo -n "$ACTOR_CLIENT_ID:$ACTOR_CLIENT_SECRET" | base64)" \
        -d "grant_type=urn:ietf:params:oauth:grant-type:token-exchange&subject_token=$SUBJECT_TOKEN&subject_token_type=urn:ietf:params:oauth:token-type:access_token&actor_token=$ACTOR_TOKEN&actor_token_type=urn:ietf:params:oauth:token-type:access_token&scope=openid%20profile%20email")
    
    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    RESPONSE_BODY=$(echo "$RESPONSE" | sed '$d')
    
    if [ "$HTTP_CODE" = "200" ]; then
        EXCHANGED_TOKEN=$(echo "$RESPONSE_BODY" | jq -r '.access_token')
        echo "$EXCHANGED_TOKEN" > .exchanged_token
        log_success "Token exchange successful"
        log_token "Exchanged token: ${EXCHANGED_TOKEN:0:20}..."
        
        # Decode and display token claims
        log_info "Exchanged token claims:"
        echo "$EXCHANGED_TOKEN" | cut -d'.' -f2 | base64 -d 2>/dev/null | jq . 2>/dev/null || echo "Unable to decode token"
    else
        log_error "Token exchange failed"
        echo "$RESPONSE_BODY" | jq . 2>/dev/null || echo "$RESPONSE_BODY"
        exit 1
    fi
}

# Cleanup
cleanup() {
    rm -f .subject_token .actor_token .exchanged_token
}

# Main execution
main() {
    echo
    log_info "🚀 Starting Token Exchange Demo"
    echo
    
    # Ensure Connect2ID is running
    if ! curl -s --fail "$SERVER_URL/.well-known/openid-configuration" > /dev/null 2>&1; then
        log_error "Connect2ID server is not running. Please run setup_c2id.sh first."
        exit 1
    fi
    
    # Run the token exchange flow
    get_subject_token
    get_actor_token
    exchange_token
    
    echo
    log_success "🎉 Token exchange demo completed successfully!"
    
    # Cleanup
    cleanup
}

# Handle script interruption
trap cleanup EXIT

main 