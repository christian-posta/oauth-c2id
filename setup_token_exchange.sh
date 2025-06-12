#!/bin/bash

# Token Exchange Setup for Connect2ID
# Extends the basic setup with token exchange configuration

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_debug() { echo -e "${YELLOW}[DEBUG]${NC} $1"; }

# Configuration
MASTER_TOKEN="ztucZS1ZyFKgh0tUEruUtiSTXhnexmd6"
SERVER_URL="http://localhost:8080/c2id"

# Register the subject token client (web client)
register_subject_client() {
    log_info "Registering subject token client..."
    
    RESPONSE=$(curl -s -w "\n%{http_code}" \
        -X POST "$SERVER_URL/clients" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $MASTER_TOKEN" \
        -d '{
            "client_name": "Subject Token Client",
            "redirect_uris": ["http://localhost:8080/oidc-client/cb"],
            "grant_types": ["authorization_code", "refresh_token", "password"],
            "response_types": ["code"],
            "token_endpoint_auth_method": "client_secret_basic",
            "scope": "openid profile email"
        }')
    
    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    RESPONSE_BODY=$(echo "$RESPONSE" | sed '$d')
    
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "201" ]; then
        SUBJECT_CLIENT_ID=$(echo "$RESPONSE_BODY" | jq -r '.client_id')
        SUBJECT_CLIENT_SECRET=$(echo "$RESPONSE_BODY" | jq -r '.client_secret')
        log_success "Subject token client registered with ID: $SUBJECT_CLIENT_ID"
        echo "$SUBJECT_CLIENT_ID" > .subject_client_id
        echo "$SUBJECT_CLIENT_SECRET" > .subject_client_secret
    else
        log_error "Failed to register subject token client"
        echo "$RESPONSE_BODY" | jq . 2>/dev/null || echo "$RESPONSE_BODY"
        return 1
    fi
}

# Register the actor token client (API client)
register_actor_client() {
    log_info "Registering actor token client..."
    
    RESPONSE=$(curl -s -w "\n%{http_code}" \
        -X POST "$SERVER_URL/clients" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $MASTER_TOKEN" \
        -d '{
            "client_name": "Actor Token Client",
            "grant_types": ["client_credentials", "urn:ietf:params:oauth:grant-type:token-exchange"],
            "token_endpoint_auth_method": "client_secret_basic",
            "scope": "token_exchange"
        }')
    
    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    RESPONSE_BODY=$(echo "$RESPONSE" | sed '$d')
    
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "201" ]; then
        ACTOR_CLIENT_ID=$(echo "$RESPONSE_BODY" | jq -r '.client_id')
        ACTOR_CLIENT_SECRET=$(echo "$RESPONSE_BODY" | jq -r '.client_secret')
        log_success "Actor token client registered with ID: $ACTOR_CLIENT_ID"
        echo "$ACTOR_CLIENT_ID" > .actor_client_id
        echo "$ACTOR_CLIENT_SECRET" > .actor_client_secret
        
        # Debug: Show client configuration
        log_debug "Actor client configuration:"
        echo "$RESPONSE_BODY" | jq . 2>/dev/null || echo "$RESPONSE_BODY"
    else
        log_error "Failed to register actor token client"
        echo "$RESPONSE_BODY" | jq . 2>/dev/null || echo "$RESPONSE_BODY"
        return 1
    fi
}

# Configure token exchange permissions
configure_token_exchange() {
    log_info "Configuring token exchange permissions..."
    
    # First, get current client configuration
    log_debug "Getting current client configuration..."
    CURRENT_CONFIG=$(curl -s \
        -H "Authorization: Bearer $MASTER_TOKEN" \
        "$SERVER_URL/clients/$ACTOR_CLIENT_ID")
    
    log_debug "Current client configuration:"
    echo "$CURRENT_CONFIG" | jq . 2>/dev/null || echo "$CURRENT_CONFIG"
    
    # Enable token exchange for the actor client
    log_debug "Updating client configuration..."
    RESPONSE=$(curl -s -w "\n%{http_code}" \
        -X PUT "$SERVER_URL/clients/$ACTOR_CLIENT_ID" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $MASTER_TOKEN" \
        -d "{
            \"client_id\": \"$ACTOR_CLIENT_ID\",
            \"client_name\": \"Actor Token Client\",
            \"grant_types\": [\"client_credentials\", \"urn:ietf:params:oauth:grant-type:token-exchange\"],
            \"token_endpoint_auth_method\": \"client_secret_basic\",
            \"scope\": \"token_exchange\",
            \"token_exchange_enabled\": true
        }")
    
    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    RESPONSE_BODY=$(echo "$RESPONSE" | sed '$d')
    
    if [ "$HTTP_CODE" = "200" ]; then
        log_success "Token exchange permissions configured"
        log_debug "Updated client configuration:"
        echo "$RESPONSE_BODY" | jq . 2>/dev/null || echo "$RESPONSE_BODY"
    else
        log_error "Failed to configure token exchange permissions"
        echo "$RESPONSE_BODY" | jq . 2>/dev/null || echo "$RESPONSE_BODY"
        return 1
    fi
}

# Main execution
main() {
    echo
    log_info "🚀 Setting up Connect2ID for Token Exchange"
    echo
    
    # Ensure Connect2ID is running
    if ! curl -s --fail "$SERVER_URL/.well-known/openid-configuration" > /dev/null 2>&1; then
        log_error "Connect2ID server is not running. Please run setup_c2id.sh first."
        exit 1
    fi
    
    # Register clients
    register_subject_client
    register_actor_client
    
    # Configure token exchange
    configure_token_exchange
    
    echo
    log_success "🎉 Token exchange setup complete!"
    log_info "Client IDs and secrets have been saved to:"
    log_info "  • .subject_client_id and .subject_client_secret"
    log_info "  • .actor_client_id and .actor_client_secret"
    echo
    log_info "You can now run: ./test_token_exchange.sh"
}

main 