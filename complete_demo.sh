#!/bin/bash

# Complete Connect2ID OAuth 2.0 Demo
# This script registers a client and demonstrates the full OAuth 2.0 flow

set -e

# Configuration
CONNECT2ID_BASE_URL="http://localhost:8080/c2id"
REDIRECT_URI="http://localhost:8080/oidc-client/cb"
CLIENT_NAME="Demo OAuth Client"
SCOPE="openid profile email"

# Master API token for client registration
MASTER_TOKEN="ztucZS1ZyFKgh0tUEruUtiSTXhnexmd6"

# Colors for output
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
log_decode() { echo -e "${CYAN}[DECODE]${NC} $1"; }

# Check dependencies
check_dependencies() {
    log_info "Checking dependencies..."
    for cmd in jq curl openssl base64; do
        if ! command -v $cmd &> /dev/null; then
            log_error "$cmd is required but not installed."
            exit 1
        fi
    done
    log_success "All dependencies are available"
}

# Get server metadata
get_server_metadata() {
    log_info "Fetching server metadata..."
    
    METADATA=$(curl -s "${CONNECT2ID_BASE_URL}/.well-known/openid-configuration")
    
    if [ $? -eq 0 ]; then
        # Get the authorization endpoint from metadata
        AUTHORIZATION_ENDPOINT=$(echo "$METADATA" | jq -r '.authorization_endpoint')
        TOKEN_ENDPOINT=$(echo "$METADATA" | jq -r '.token_endpoint')
        USERINFO_ENDPOINT=$(echo "$METADATA" | jq -r '.userinfo_endpoint')
        REGISTRATION_ENDPOINT=$(echo "$METADATA" | jq -r '.registration_endpoint // "not_supported"')
        ISSUER=$(echo "$METADATA" | jq -r '.issuer')
        
        # Debug: Show raw metadata
        log_info "Raw server metadata:"
        echo "$METADATA" | jq .
        echo
        
        # Ensure we're using localhost consistently
        AUTHORIZATION_ENDPOINT=$(echo "$AUTHORIZATION_ENDPOINT" | sed 's/127.0.0.1/localhost/g')
        TOKEN_ENDPOINT=$(echo "$TOKEN_ENDPOINT" | sed 's/127.0.0.1/localhost/g')
        USERINFO_ENDPOINT=$(echo "$USERINFO_ENDPOINT" | sed 's/127.0.0.1/localhost/g')
        REGISTRATION_ENDPOINT=$(echo "$REGISTRATION_ENDPOINT" | sed 's/127.0.0.1/localhost/g')
        ISSUER=$(echo "$ISSUER" | sed 's/127.0.0.1/localhost/g')
        
        # If authorization endpoint is not set, use the default
        if [ -z "$AUTHORIZATION_ENDPOINT" ] || [ "$AUTHORIZATION_ENDPOINT" = "null" ]; then
            AUTHORIZATION_ENDPOINT="http://localhost:8080/c2id/authorize"
            log_warning "Using default authorization endpoint: $AUTHORIZATION_ENDPOINT"
        fi
        
        log_success "Server metadata retrieved"
        log_info "Issuer: $ISSUER"
        log_info "Authorization endpoint: $AUTHORIZATION_ENDPOINT"
        log_info "Token endpoint: $TOKEN_ENDPOINT"
        log_info "Registration endpoint: $REGISTRATION_ENDPOINT"
        echo
    else
        log_error "Failed to fetch server metadata"
        exit 1
    fi
}

# Register a new client
register_client() {
    log_step "STEP 1: Register OAuth 2.0 Client"
    echo
    
    if [ "$REGISTRATION_ENDPOINT" = "not_supported" ]; then
        log_error "Client registration is not supported by this server"
        exit 1
    fi
    
    log_info "Registering new OAuth 2.0 client..."
    log_info "Redirect URI: $REDIRECT_URI"
    log_info "Client name: $CLIENT_NAME"
    
    # Prepare registration request
    REGISTRATION_REQUEST=$(cat <<EOF
{
    "redirect_uris": ["$REDIRECT_URI"],
    "grant_types": ["authorization_code", "refresh_token"],
    "response_types": ["code"],
    "client_name": "$CLIENT_NAME",
    "scope": "$SCOPE",
    "token_endpoint_auth_method": "client_secret_basic"
}
EOF
)
    
    log_info "Registration request:"
    echo "$REGISTRATION_REQUEST" | jq .
    echo
    
    # Make registration request
    RESPONSE=$(curl -s -w "\n%{http_code}" \
        -X POST "$REGISTRATION_ENDPOINT" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $MASTER_TOKEN" \
        -d "$REGISTRATION_REQUEST")
    
    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    RESPONSE_BODY=$(echo "$RESPONSE" | sed '$d')
    
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "201" ]; then
        log_success "✅ Client registration successful!"
        echo
        
        # Parse client details
        CLIENT_ID=$(echo "$RESPONSE_BODY" | jq -r '.client_id')
        CLIENT_SECRET=$(echo "$RESPONSE_BODY" | jq -r '.client_secret // "none"')
        
        log_success "📋 CLIENT DETAILS:"
        echo "$RESPONSE_BODY" | jq .
        echo
        
        log_info "Client ID: $CLIENT_ID"
        if [ "$CLIENT_SECRET" != "none" ]; then
            log_info "Client Secret: ${CLIENT_SECRET:0:20}... (truncated for security)"
        fi
        echo
        
    else
        log_error "❌ Client registration failed with HTTP $HTTP_CODE"
        log_error "Response: $RESPONSE_BODY"
        exit 1
    fi
}

# Generate PKCE parameters
generate_pkce() {
    log_info "Generating PKCE parameters for security..."
    
    # RFC 7636: Generate code verifier (43-128 chars from unreserved char set)
    # Using base64url without padding for allowed characters
    # Generate more bytes to ensure we have enough characters after transformations
    CODE_VERIFIER=$(openssl rand 48 | openssl base64 | tr -d "=+/" | tr -d '\n' | cut -c1-43)
    
    # Verify length
    if [ ${#CODE_VERIFIER} -lt 43 ]; then
        log_error "Generated code verifier is too short (${#CODE_VERIFIER} chars)"
        exit 1
    fi
    
    # Generate code challenge: base64url(sha256(code_verifier))
    CODE_CHALLENGE=$(echo -n "$CODE_VERIFIER" | openssl dgst -binary -sha256 | openssl base64 | tr -d "=+/" | tr "/+" "_-")
    
    log_success "PKCE parameters generated"
    log_info "Code Verifier: $CODE_VERIFIER"
    log_info "Code Verifier length: ${#CODE_VERIFIER}"
    log_info "Code Challenge: $CODE_CHALLENGE"
    echo
}

# Generate authorization URL
generate_auth_url() {
    log_step "STEP 2: Generate Authorization URL"
    echo
    
    # Generate state parameter
    STATE=$(openssl rand -hex 16)
    
    # Build authorization URL using the endpoint from discovery
    AUTH_URL="${AUTHORIZATION_ENDPOINT}?response_type=code&client_id=${CLIENT_ID}&redirect_uri=${REDIRECT_URI}&scope=${SCOPE// /%20}&state=${STATE}&code_challenge=${CODE_CHALLENGE}&code_challenge_method=S256"
    
    log_success "✅ Authorization URL generated:"
    echo
    echo "🔗 $AUTH_URL"
    echo
    
    log_info "This URL includes:"
    log_info "  • client_id=$CLIENT_ID (our registered client)"
    log_info "  • redirect_uri=$REDIRECT_URI (registered callback)"
    log_info "  • scope=$SCOPE (requested permissions)"
    log_info "  • PKCE challenge for security"
    log_info "  • Authorization endpoint: $AUTHORIZATION_ENDPOINT"
    echo
}

# Get authorization code
get_authorization_code() {
    log_step "STEP 3: Get Authorization Code"
    echo
    
    log_info "🌐 Please:"
    log_info "1. Copy the authorization URL above"
    log_info "2. Open it in your browser"
    log_info "3. Complete the login process"
    log_info "4. You'll be redirected to a URL that looks like:"
    log_info "   $REDIRECT_URI?code=...&state=..."
    log_info "5. Copy and paste the COMPLETE redirect URL below"
    echo
    
    read -p "$(echo -e "${BLUE}Paste the complete callback URL:${NC} ")" CALLBACK_URL
    
    if [ -z "$CALLBACK_URL" ]; then
        log_error "No callback URL provided"
        exit 1
    fi
    
    # Parse the URL to extract the authorization code
    log_info "Parsing callback URL..."
    
    # Extract query parameters using parameter expansion
    if [[ "$CALLBACK_URL" == *"?"* ]]; then
        QUERY_STRING="${CALLBACK_URL#*\?}"
        
        # Parse authorization code
        if [[ "$QUERY_STRING" == *"code="* ]]; then
            AUTHORIZATION_CODE=$(echo "$QUERY_STRING" | sed 's/.*code=\([^&]*\).*/\1/')
            # URL decode the code
            AUTHORIZATION_CODE=$(printf '%b' "${AUTHORIZATION_CODE//%/\\x}")
        else
            log_error "No 'code' parameter found in callback URL"
            exit 1
        fi
        
        # Parse state for verification
        if [[ "$QUERY_STRING" == *"state="* ]]; then
            RECEIVED_STATE=$(echo "$QUERY_STRING" | sed 's/.*state=\([^&]*\).*/\1/')
            log_info "Received state: $RECEIVED_STATE"
            log_info "Expected state: $STATE"
            
            if [ "$RECEIVED_STATE" != "$STATE" ]; then
                log_warning "⚠️  State parameter mismatch - possible CSRF attack!"
                log_warning "Continuing anyway for demo purposes..."
            else
                log_success "✅ State parameter verified"
            fi
        fi
        
        # Check for error parameters
        if [[ "$QUERY_STRING" == *"error="* ]]; then
            ERROR_CODE=$(echo "$QUERY_STRING" | sed 's/.*error=\([^&]*\).*/\1/')
            ERROR_DESC=""
            if [[ "$QUERY_STRING" == *"error_description="* ]]; then
                ERROR_DESC=$(echo "$QUERY_STRING" | sed 's/.*error_description=\([^&]*\).*/\1/')
                ERROR_DESC=$(printf '%b' "${ERROR_DESC//%/\\x}")
            fi
            
            log_error "❌ Authorization failed!"
            log_error "Error: $ERROR_CODE"
            if [ -n "$ERROR_DESC" ]; then
                log_error "Description: $ERROR_DESC"
            fi
            exit 1
        fi
        
    else
        log_error "Invalid callback URL format - no query parameters found"
        exit 1
    fi
    
    if [ -z "$AUTHORIZATION_CODE" ]; then
        log_error "Failed to extract authorization code from URL"
        exit 1
    fi
    
    log_success "✅ Authorization code extracted: ${AUTHORIZATION_CODE:0:20}..."
    log_info "Full code: $AUTHORIZATION_CODE"
    echo
}

# Exchange code for tokens
exchange_code_for_tokens() {
    log_step "STEP 4: Exchange Code for Tokens"
    echo
    
    log_info "Exchanging authorization code for access token..."
    log_info "Making token request to: $TOKEN_ENDPOINT"
    
    # Prepare token request data
    TOKEN_DATA="grant_type=authorization_code&code=${AUTHORIZATION_CODE}&redirect_uri=${REDIRECT_URI}&code_verifier=${CODE_VERIFIER}"
    
    # Debug logging
    log_info "Token request details:"
    log_info "  • Grant Type: authorization_code"
    log_info "  • Code: ${AUTHORIZATION_CODE:0:20}..."
    log_info "  • Redirect URI: $REDIRECT_URI"
    log_info "  • Code Verifier: ${CODE_VERIFIER:0:20}..."
    log_info "  • Code Challenge: ${CODE_CHALLENGE:0:20}..."
    log_info "  • Full Code Verifier: $CODE_VERIFIER"
    log_info "  • Full Code Challenge: $CODE_CHALLENGE"
    log_info "  • Authorization Endpoint Used: $AUTHORIZATION_ENDPOINT"
    
    # Make token request with proper client authentication
    if [ "$CLIENT_SECRET" != "none" ] && [ -n "$CLIENT_SECRET" ]; then
        # Use HTTP Basic authentication
        log_info "Using client_secret_basic authentication"
        RESPONSE=$(curl -s -w "\n%{http_code}" \
            -X POST "$TOKEN_ENDPOINT" \
            -H "Content-Type: application/x-www-form-urlencoded" \
            -u "${CLIENT_ID}:${CLIENT_SECRET}" \
            -d "$TOKEN_DATA")
    else
        # Include client_id in request body for public clients
        log_info "Using public client authentication"
        TOKEN_DATA="${TOKEN_DATA}&client_id=${CLIENT_ID}"
        RESPONSE=$(curl -s -w "\n%{http_code}" \
            -X POST "$TOKEN_ENDPOINT" \
            -H "Content-Type: application/x-www-form-urlencoded" \
            -d "$TOKEN_DATA")
    fi
    
    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    RESPONSE_BODY=$(echo "$RESPONSE" | sed '$d')
    
    if [ "$HTTP_CODE" = "200" ]; then
        log_success "✅ Token exchange successful!"
        echo
        
        # Parse tokens
        ACCESS_TOKEN=$(echo "$RESPONSE_BODY" | jq -r '.access_token')
        REFRESH_TOKEN=$(echo "$RESPONSE_BODY" | jq -r '.refresh_token // "none"')
        ID_TOKEN=$(echo "$RESPONSE_BODY" | jq -r '.id_token // "none"')
        TOKEN_TYPE=$(echo "$RESPONSE_BODY" | jq -r '.token_type')
        EXPIRES_IN=$(echo "$RESPONSE_BODY" | jq -r '.expires_in')
        
        log_success "🎫 TOKEN RESPONSE:"
        echo "$RESPONSE_BODY" | jq .
        echo
        
        log_info "Token Details:"
        log_info "  • Access Token: ${ACCESS_TOKEN:0:30}..."
        log_info "  • Token Type: $TOKEN_TYPE"
        log_info "  • Expires In: $EXPIRES_IN seconds"
        if [ "$ID_TOKEN" != "none" ]; then
            log_info "  • ID Token: ${ID_TOKEN:0:30}..."
        fi
        if [ "$REFRESH_TOKEN" != "none" ]; then
            log_info "  • Refresh Token: ${REFRESH_TOKEN:0:30}..."
        fi
        echo
        
    else
        log_error "❌ Token exchange failed with HTTP $HTTP_CODE"
        log_error "Response: $RESPONSE_BODY"
        
        # Debug information
        log_error "Debug info:"
        log_error "  • Token endpoint: $TOKEN_ENDPOINT"
        log_error "  • Client ID: $CLIENT_ID"
        log_error "  • Auth code length: ${#AUTHORIZATION_CODE}"
        log_error "  • Code verifier length: ${#CODE_VERIFIER}"
        log_error "  • Redirect URI: $REDIRECT_URI"
        log_error "  • Code Challenge: $CODE_CHALLENGE"
        log_error "  • Full Code Verifier: $CODE_VERIFIER"
        log_error "  • Authorization Endpoint Used: $AUTHORIZATION_ENDPOINT"
        
        exit 1
    fi
}

# Decode JWT token
decode_jwt() {
    local token=$1
    local token_name=$2
    
    log_decode "=== Decoding $token_name ==="
    echo
    
    IFS='.' read -ra TOKEN_PARTS <<< "$token"
    
    if [ ${#TOKEN_PARTS[@]} -ne 3 ]; then
        log_error "Invalid JWT format"
        return 1
    fi
    
    local header=${TOKEN_PARTS[0]}
    local payload=${TOKEN_PARTS[1]}
    
    log_decode "📋 JWT Header:"
    header_padded="${header}$(printf '%*s' $((4 - ${#header} % 4)) | tr ' ' '=')"
    header_decoded=$(echo "$header_padded" | base64 -d 2>/dev/null || echo "Could not decode")
    if [ "$header_decoded" != "Could not decode" ]; then
        echo "$header_decoded" | jq . 2>/dev/null || echo "$header_decoded"
    fi
    echo
    
    log_decode "📄 JWT Payload (Claims):"
    payload_padded="${payload}$(printf '%*s' $((4 - ${#payload} % 4)) | tr ' ' '=')"
    payload_decoded=$(echo "$payload_padded" | base64 -d 2>/dev/null || echo "Could not decode")
    if [ "$payload_decoded" != "Could not decode" ]; then
        echo "$payload_decoded" | jq . 2>/dev/null || echo "$payload_decoded"
        
        echo
        log_decode "🔍 Key Claims:"
        if echo "$payload_decoded" | jq . >/dev/null 2>&1; then
            local sub=$(echo "$payload_decoded" | jq -r '.sub // "not present"')
            local iss=$(echo "$payload_decoded" | jq -r '.iss // "not present"')
            local aud=$(echo "$payload_decoded" | jq -r '.aud // "not present"')
            local exp=$(echo "$payload_decoded" | jq -r '.exp // "not present"')
            local scope=$(echo "$payload_decoded" | jq -r '.scope // "not present"')
            
            log_decode "  Subject (user): $sub"
            log_decode "  Issuer: $iss"
            log_decode "  Audience: $aud"
            log_decode "  Scope: $scope"
            
            if [ "$exp" != "not present" ] && [ "$exp" != "null" ]; then
                local exp_date=$(date -d "@$exp" 2>/dev/null || echo "Invalid")
                log_decode "  Expires: $exp ($exp_date)"
            fi
        fi
    fi
    echo
}

# Use access token
use_access_token() {
    log_step "STEP 5: Use Access Token"
    echo
    
    log_info "Making UserInfo request to: $USERINFO_ENDPOINT"
    
    RESPONSE=$(curl -s -w "\n%{http_code}" \
        -X GET "$USERINFO_ENDPOINT" \
        -H "Authorization: Bearer $ACCESS_TOKEN")
    
    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    RESPONSE_BODY=$(echo "$RESPONSE" | sed '$d')
    
    if [ "$HTTP_CODE" = "200" ]; then
        log_success "✅ UserInfo request successful!"
        echo
        log_info "👤 User Information:"
        echo "$RESPONSE_BODY" | jq . 2>/dev/null || echo "$RESPONSE_BODY"
        echo
    else
        log_warning "❌ UserInfo request failed with HTTP $HTTP_CODE"
        log_warning "Response: $RESPONSE_BODY"
    fi
}

# Main execution
main() {
    echo
    log_info "🚀 Complete Connect2ID OAuth 2.0 Demo"
    log_info "This demo registers a client and demonstrates the full OAuth 2.0 flow"
    echo
    
    check_dependencies
    echo
    
    get_server_metadata
    register_client
    generate_pkce
    generate_auth_url
    get_authorization_code
    exchange_code_for_tokens
    
    # Decode tokens
    if [ -n "$ACCESS_TOKEN" ] && [ "$ACCESS_TOKEN" != "null" ]; then
        decode_jwt "$ACCESS_TOKEN" "Access Token"
    fi
    
    if [ "$ID_TOKEN" != "none" ] && [ "$ID_TOKEN" != "null" ]; then
        decode_jwt "$ID_TOKEN" "ID Token"
    fi
    
    use_access_token
    
    echo
    log_success "🎉 Complete OAuth 2.0 Demo completed!"
    log_info "You've successfully:"
    log_info "  • Registered a new OAuth 2.0 client"
    log_info "  • Completed the authorization code flow with PKCE"
    log_info "  • Exchanged authorization code for tokens"
    log_info "  • Decoded and analyzed JWT tokens"
    log_info "  • Used access token to call protected API"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --server)
            CONNECT2ID_BASE_URL="$2"
            shift 2
            ;;
        --redirect-uri)
            REDIRECT_URI="$2"
            shift 2
            ;;
        --master-token)
            MASTER_TOKEN="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --server URL          Connect2ID server URL"
            echo "  --redirect-uri URI    OAuth 2.0 redirect URI"
            echo "  --master-token TOKEN  Master API token for client registration"
            echo "  --help, -h            Show this help"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

main