# Connect2ID Demo Setup Guide

This guide uses the Connect2ID demo Docker image which includes everything pre-configured for testing.

## Quick Start

### 1. Create the Docker Compose setup

Save the provided `docker-compose.yml` file and run:

```bash
docker run -d   --name connect2id-demo   -p 8080:8080   -p 8443:8443   -e CATALINA_OPTS="-Xmx2048m -Xms1024m"   c2id/c2id-server-demo:18.2.1

docker logs connect2id-demo

# Check server status
curl -s http://localhost:8080/c2id/.well-known/openid-configuration | jq .
```

### 2. Run the demo test script

```bash
# Make the test script executable
chmod +x demo_test.sh

# Run the test to discover demo configuration
./demo_test.sh
```

## What the Demo Image Includes

The `c2id/c2id-server-demo` image comes with:

- ✅ **Pre-configured demo clients**
- ✅ **Sample users for testing**
- ✅ **Complete OpenID Connect/OAuth 2.0 setup**
- ✅ **Built-in H2 database with demo data**
- ✅ **Sample login pages**
- ✅ **Working OAuth 2.0 flows out of the box**

## Testing Flows

### 1. Automatic Discovery
The test script will automatically try common demo client IDs and user credentials:

**Common Demo Clients:**
- `000123`
- `demo`
- `test`
- `client`

**Common Demo Users:**
- `alice:secret`
- `bob:secret`
- `demo:demo`
- `test:test`

### 2. Manual Testing

If you know the specific demo credentials, you can test manually:

```bash
# Test password flow with known credentials
curl -X POST http://localhost:8080/token \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=password&username=alice&password=secret&client_id=000123"

# Or with client authentication
CLIENT_CREDENTIALS=$(echo -n "client_id:client_secret" | base64)
curl -X POST http://localhost:8080/token \
  -H "Authorization: Basic $CLIENT_CREDENTIALS" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=password&username=alice&password=secret"
```

### 3. Authorization Code Flow

The test script will generate a complete authorization URL for browser testing:

1. Open the generated URL in your browser
2. Complete the authentication flow
3. Get redirected with an authorization code
4. Exchange the code for tokens

## Server Endpoints

With the demo server running:

- **Discovery**: `http://localhost:8080/.well-known/openid-configuration`
- **Authorization**: Check discovery document for exact URL
- **Token**: Check discovery document for exact URL
- **UserInfo**: Check discovery document for exact URL
- **Main Page**: `http://localhost:8080/` (may contain demo instructions)

## Advantages of the Demo Image

1. **Zero Configuration**: Works immediately without setup
2. **Complete Examples**: Includes working flows and sample data
3. **Learning Tool**: Perfect for understanding OpenID Connect/OAuth 2.0
4. **Quick Testing**: Ideal for integration testing and development

## Next Steps

Once you have the demo working:

1. **Explore the demo clients and users**
2. **Test different OAuth 2.0 flows**
3. **Build your own client application**
4. **Move to production configuration when ready**

## Troubleshooting

### Server Won't Start
```bash
# Check Docker logs
docker-compose logs connect2id

# Verify port availability
netstat -tlnp | grep 8080

# Check Docker image
docker images | grep c2id
```

### Can't Find Demo Credentials
- Check the main server page at `http://localhost:8080/`
- Look for demo documentation in the Connect2ID logs
- The test script will try to discover working combinations automatically

### Connection Issues
```bash
# Test basic connectivity
curl -v http://localhost:8080/.well-known/openid-configuration

# Check if server is responding
docker-compose ps
```

This demo setup should get you up and running with Connect2ID immediately, without any of the configuration complexity we encountered with the minimal image!