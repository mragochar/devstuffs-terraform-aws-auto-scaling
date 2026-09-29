#!/bin/bash

# Wait for apt/dpkg locks to clear
while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do
    sleep 2
done

# Update package lists and install Nginx
apt-get update
apt-get install -y nginx

# Get IMDSv2 token
TOKEN=$(curl -sS --max-time 5 \
    -X PUT \
    "http://169.254.169.254/latest/api/token" \
    -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")

HOSTNAME=$(hostname)

# Get private IP from EC2 metadata
PRIVATE_IP=$(curl -sS --max-time 5 \
    -H "X-aws-ec2-metadata-token: $TOKEN" \
    "http://169.254.169.254/latest/meta-data/local-ipv4")

# Fallback if metadata is unavailable
if [ -z "$PRIVATE_IP" ]; then
    PRIVATE_IP=$(hostname -I | awk '{print $1}')
fi

# Write HTML
cat > /var/www/html/index.html <<EOF
<!DOCTYPE html>
<html>
<head>
    <title>ALB Demo</title>
</head>
<body>
    <h1>Hello from EC2</h1>

    <p><strong>Hostname:</strong> $HOSTNAME</p>
    <p><strong>Private IP:</strong> $PRIVATE_IP</p>
</body>
</html>
EOF

# Enable and start Nginx
systemctl enable nginx
systemctl start nginx