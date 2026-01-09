#!/bin/bash
set -ex

# Log output
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

echo "Starting Book Library Application Setup..."

# Update system packages
dnf update -y

# Install required packages
dnf install -y python3.11 python3.11-pip nginx git unzip

# Create application directory
mkdir -p /opt/book-library
cd /opt/book-library

# Wait for S3 bucket to be available and download application
echo "Downloading application from S3..."
max_retries=30
retry_count=0

while [ $retry_count -lt $max_retries ]; do
  if aws s3 cp s3://${s3_bucket}/application.zip /opt/book-library/application.zip --region ${aws_region} 2>/dev/null; then
    echo "Application downloaded successfully"
    unzip -o application.zip
    break
  else
    echo "Waiting for application in S3 (attempt $((retry_count + 1))/$max_retries)..."
    sleep 10
    retry_count=$((retry_count + 1))
  fi
done

if [ ! -f /opt/book-library/app.py ]; then
  echo "Application not found in S3, creating placeholder..."
  # Create a basic placeholder if S3 download fails
  cat > /opt/book-library/app.py << 'PLACEHOLDER_EOF'
from flask import Flask
app = Flask(__name__)

@app.route('/')
def home():
    return '<h1>Book Library - Waiting for deployment</h1><p>Application code not yet deployed. Please upload to S3.</p>'

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
PLACEHOLDER_EOF
fi

# Install Python dependencies
pip3.11 install flask gunicorn

# Create systemd service
cat > /etc/systemd/system/book-library.service << 'EOF'
[Unit]
Description=Book Library Flask Application
After=network.target

[Service]
User=root
WorkingDirectory=/opt/book-library
Environment="PATH=/usr/local/bin:/usr/bin"
ExecStart=/usr/bin/python3.11 -m gunicorn --workers 3 --bind 0.0.0.0:5000 app:app
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Configure Nginx as reverse proxy
cat > /etc/nginx/conf.d/book-library.conf << 'EOF'
server {
    listen 80;
    server_name _;

    location / {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location /static {
        alias /opt/book-library/static;
        expires 30d;
    }
}
EOF

# Remove default nginx config
rm -f /etc/nginx/conf.d/default.conf

# Start services
systemctl daemon-reload
systemctl enable book-library
systemctl start book-library
systemctl enable nginx
systemctl start nginx

echo "Book Library Application Setup Complete!"
echo "Application should be available on port 80"
