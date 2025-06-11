# Connect2ID OAuth 2.0 Demo

This repository contains a complete OAuth 2.0 demo script that demonstrates the full authorization code flow with PKCE using Connect2ID as the OAuth 2.0/OpenID Connect provider.

## Prerequisites

- Docker
- `curl`
- `jq`
- `openssl`
- `base64`

## Setup

### 1. Start the Connect2ID Demo Server

```bash
# Make the setup script executable
chmod +x setup_c2id.sh

# Run the setup script
./setup_c2id.sh
```

The setup script will:
- Clean up any existing Connect2ID container
- Start a new container with proper configuration
- Configure necessary Java system properties:
  - Enable localhost redirect URIs for testing
  - Enable open registration
  - Set the issuer URL
- Wait for the server to start
- Test the configuration with a sample client registration
- Show server information and status

### 2. Prepare the Demo Script

```bash
# Make the demo script executable
chmod +x complete_demo.sh
```

## Running the Demo

### Basic Usage

```bash
./complete_demo.sh
```

### Advanced Options

The script supports several command-line options:

```bash
./complete_demo.sh [OPTIONS]

Options:
  --server URL          Connect2ID server URL (default: http://localhost:8080/c2id)
  --redirect-uri URI    OAuth 2.0 redirect URI (default: http://localhost:8080/oidc-client/cb)
  --master-token TOKEN  Master API token for client registration
  --help, -h           Show help message
```

## What the Demo Does

The script demonstrates a complete OAuth 2.0 authorization code flow with PKCE:

1. **Client Registration**
   - Registers a new OAuth 2.0 client with the server
   - Configures redirect URI and required scopes

2. **Authorization Request**
   - Generates PKCE parameters for security
   - Creates authorization URL with proper parameters
   - Handles state parameter for CSRF protection

3. **Token Exchange**
   - Exchanges authorization code for tokens
   - Supports both confidential and public clients
   - Implements proper client authentication

4. **Token Usage**
   - Decodes and displays JWT tokens
   - Makes a UserInfo request with the access token
   - Shows token details and claims

## Demo Credentials

The Connect2ID demo server comes with pre-configured users:

- Username: `alice`
- Password: `secret`

## Troubleshooting

### Common Issues

1. **Server Not Running**
   ```bash
   # Check if server is running
   docker ps | grep connect2id-demo
   
   # Check server logs
   docker logs connect2id-demo
   ```

2. **Connection Issues**
   ```bash
   # Test server connectivity
   curl -v http://localhost:8080/c2id/.well-known/openid-configuration
   ```

3. **Script Errors**
   - Ensure all prerequisites are installed
   - Check script permissions (`chmod +x setup_c2id.sh complete_demo.sh`)
   - Verify server is running before starting the demo script

### Debug Information

The scripts include detailed logging:
- Blue: Information messages
- Green: Success messages
- Yellow: Warnings
- Red: Errors
- Purple: Step indicators
- Cyan: Token decoding information

## Security Notes

- The demo uses PKCE for enhanced security
- State parameter prevents CSRF attacks
- Client secrets are never logged in full
- Tokens are truncated in logs for security
- Server is configured to allow localhost redirect URIs for testing

## Next Steps

After running the demo:
1. Review the token responses and claims
2. Try different scopes and client configurations
3. Experiment with different OAuth 2.0 flows
4. Implement the flow in your own application

## License

This demo script is provided for educational purposes. Use at your own risk.