#!/bin/bash

# Direct Configuration Setup for Connect2ID
# Uses Java system properties instead of override.properties file

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

# Stop existing container
cleanup_existing() {
    log_info "Cleaning up existing Connect2ID container..."
    
    if docker ps -a | grep -q connect2id-demo; then
        docker stop connect2id-demo 2>/dev/null || true
        docker rm connect2id-demo 2>/dev/null || true
        log_success "Existing container removed"
    else
        log_info "No existing container found"
    fi
}

# Start Connect2ID with Java system properties
start_connect2id_with_java_props() {
    log_info "Starting Connect2ID with Java system properties configuration..."
    
    # Create logs directory
    mkdir -p logs
    LOGS_PATH=$(realpath logs)
    
    # Start container with Java system properties for configuration
    docker run -d \
        --name connect2id-demo \
        -p 8080:8080 \
        -p 8443:8443 \
        --mount type=bind,source="$LOGS_PATH",target=/usr/local/tomcat/logs \
        -e CATALINA_OPTS="-Xmx2048m -Xms1024m" \
        -e JAVA_OPTS="-Dlog4j2.formatMsgNoLookups=true \
            -Dop.reg.allowLocalhostRedirectionURIsForTest=true \
            -Dop.reg.rejectNonTLSRedirectionURIs=false \
            -Dop.reg.enableOpenRegistration=true \
            -Dop.issuer=http://localhost:8080/c2id \
            -Dop.grantHandler.tokenExchange.webAPI.enable=true \
            -Dop.grantHandler.tokenExchange.webAPI.url=http://localhost:8080/c2id/token-exchange \
            -Dop.grantHandler.tokenExchange.webAPI.apiAccessToken=ztucZS1ZyFKgh0tUEruUtiSTXhnexmd6 \
            -Dop.grantHandler.tokenExchange.webAPI.subjectToken.types=urn:ietf:params:oauth:token-type:access_token \
            -Dop.grantHandler.tokenExchange.webAPI.actorToken.types=urn:ietf:params:oauth:token-type:access_token \
            -Dop.grantHandler.tokenExchange.webAPI.subjectToken.jwtVerification.1.jwkSetURI=http://localhost:8080/c2id/jwks.json \
            -Dop.grantHandler.tokenExchange.webAPI.actorToken.jwtVerification.1.jwkSetURI=http://localhost:8080/c2id/jwks.json" \
        c2id/c2id-server-demo:18.2.1
    
    log_success "Connect2ID container started with Java system properties"
    log_info "Configuration set via JAVA_OPTS:"
    log_info "  • op.reg.allowLocalhostRedirectionURIsForTest=true"
    log_info "  • op.reg.rejectNonTLSRedirectionURIs=false"
    log_info "  • op.reg.enableOpenRegistration=true"
    log_info "  • op.issuer=http://localhost:8080/c2id"
}

# Wait for server startup
wait_for_startup() {
    log_info "Waiting for Connect2ID server to start..."
    
    local count=0
    local max_retries=30
    
    while [ $count -lt $max_retries ]; do
        if curl -s --fail "http://localhost:8080/c2id/.well-known/openid-configuration" > /dev/null 2>&1; then
            log_success "✅ Server is running!"
            return 0
        fi
        
        count=$((count + 1))
        echo -n "."
        sleep 2
    done
    
    echo
    log_error "Server failed to start after $((max_retries * 2)) seconds"
    log_info "Container logs:"
    docker logs connect2id-demo | tail -20
    return 1
}

# Test configuration
test_localhost_registration() {
    log_info "Testing localhost redirect URI registration..."
    
    # Test client registration with localhost URI
    RESPONSE=$(curl -s -w "\n%{http_code}" \
        -X POST "http://localhost:8080/c2id/clients" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer ztucZS1ZyFKgh0tUEruUtiSTXhnexmd6" \
        -d '{
            "redirect_uris": ["http://localhost:8080/test-callback"],
            "client_name": "Test Client",
            "grant_types": ["authorization_code"],
            "response_types": ["code"]
        }')
    
    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    RESPONSE_BODY=$(echo "$RESPONSE" | sed '$d')
    
    echo
    log_info "Registration response (HTTP $HTTP_CODE):"
    echo "$RESPONSE_BODY" | jq . 2>/dev/null || echo "$RESPONSE_BODY"
    echo
    
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "201" ]; then
        log_success "✅ Localhost redirect URIs are working!"
        
        CLIENT_ID=$(echo "$RESPONSE_BODY" | jq -r '.client_id // "unknown"')
        if [ "$CLIENT_ID" != "unknown" ]; then
            log_info "Test client registered with ID: $CLIENT_ID"
            
            # Clean up test client
            curl -s -X DELETE "http://localhost:8080/c2id/clients/$CLIENT_ID" \
                -H "Authorization: Bearer ztucZS1ZyFKgh0tUEruUtiSTXhnexmd6" > /dev/null 2>&1 || true
        fi
        
        return 0
    else
        log_error "❌ Configuration still not working"
        
        # Show more detailed logs
        log_info "Recent container logs:"
        docker logs connect2id-demo | tail -30
        
        return 1
    fi
}

# Show server info
show_server_info() {
    log_info "Server information:"
    
    local metadata=$(curl -s "http://localhost:8080/c2id/.well-known/openid-configuration")
    if [ $? -eq 0 ]; then
        local issuer=$(echo "$metadata" | jq -r '.issuer // "unknown"')
        local registration_endpoint=$(echo "$metadata" | jq -r '.registration_endpoint // "unknown"')
        
        log_info "  • Issuer: $issuer"
        log_info "  • Registration endpoint: $registration_endpoint"
        log_info "  • Master API Token: ztucZS1ZyFKgh0tUEruUtiSTXhnexmd6"
        
        # Try to get version info
        local version_info=$(curl -s "http://localhost:8080/c2id/" | grep -i version || echo "Version not found")
        log_info "  • Version info: $version_info"
    fi
}

# Main execution
main() {
    echo
    log_info "🚀 Direct Configuration Setup for Connect2ID"
    log_info "Using Java system properties instead of override file"
    echo
    
    cleanup_existing
    start_connect2id_with_java_props
    
    if wait_for_startup; then
        show_server_info
        echo
        
        if test_localhost_registration; then
            echo
            log_success "🎉 Connect2ID is properly configured!"
            log_info "You can now run: ./complete_demo.sh"
        else
            log_error "Configuration failed. Check the logs above."
            exit 1
        fi
    else
        log_error "Server startup failed"
        exit 1
    fi
}

main