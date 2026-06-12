# Accessing the Application from Other Computers

## Current Configuration

The Flask application is already configured to accept connections from other computers (`host='0.0.0.0'`).

## Steps to Access from Other Computers

### 1. Find Your Computer's IP Address

**On macOS:**
```bash
ifconfig | grep "inet " | grep -v 127.0.0.1
```
Or:
```bash
ipconfig getifaddr en0
```

**On Windows:**
```bash
ipconfig
```
Look for "IPv4 Address" under your active network adapter.

**On Linux:**
```bash
hostname -I
```
Or:
```bash
ip addr show
```

### 2. Start the Application

Make sure the app is running with:
```bash
cd data-entry-app
python3 app.py
```

The app should show something like:
```
 * Running on http://0.0.0.0:5000
```

### 3. Access from Other Computers

From any computer on the **same network**, open a web browser and go to:
```
http://YOUR_IP_ADDRESS:5000
```

For example, if your IP is `192.168.1.100`:
```
http://192.168.1.100:5000
```

## Important Notes

### Firewall Settings

**On macOS:**
- Go to System Preferences → Security & Privacy → Firewall
- Make sure Python is allowed to accept incoming connections
- Or temporarily disable firewall for testing

**On Windows:**
- Go to Windows Defender Firewall
- Allow Python through the firewall
- Or add an exception for port 5000

**On Linux:**
```bash
sudo ufw allow 5000
```

### Network Requirements

- Both computers must be on the **same local network** (same Wi-Fi/router)
- The computer running the app must have its firewall configured to allow connections
- Make sure no other application is using port 5000

### Security Considerations

⚠️ **Warning**: Running on `0.0.0.0` makes your app accessible to anyone on your local network. For production use, consider:

1. **Use HTTPS** with SSL certificates
2. **Add authentication** (login/password)
3. **Use a reverse proxy** (nginx, Apache)
4. **Deploy to a cloud service** (Google Cloud Run, AWS, etc.)

### Troubleshooting

**Can't connect from other computer:**
1. Check firewall settings
2. Verify both computers are on the same network
3. Try pinging the IP address: `ping YOUR_IP_ADDRESS`
4. Check if port 5000 is open: `telnet YOUR_IP_ADDRESS 5000`

**Connection refused:**
- Make sure the app is running
- Check if another process is using port 5000
- Try a different port (change `port=5000` to `port=8080` in app.py)

**Can access from same computer but not others:**
- Firewall is likely blocking the connection
- Check firewall settings as described above

## Alternative: Deploy to Cloud

For better accessibility and security, consider deploying to:
- **Google Cloud Run** (serverless, pay per use)
- **Google App Engine** (managed platform)
- **Heroku** (easy deployment)
- **DigitalOcean** (VPS hosting)
