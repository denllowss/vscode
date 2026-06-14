FROM codercom/code-server:latest
USER root

# Install OpenSSH server
RUN apt-get update && apt-get install -y openssh-server iproute2 && \
    mkdir -p /var/run/sshd && \
    rm -rf /var/lib/apt/lists/*

# Buat entrypoint script
RUN cat > /entrypoint.sh << 'EOF'
#!/bin/bash

# Password default
SSH_PASS="root"

# Set password root
echo "root:${SSH_PASS}" | chpasswd

# Konfigurasi SSH
sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config

# Start SSH daemon
service ssh start

# Ambil IP address
IP_ADDR=$(hostname -I | awk '{print $1}')

# Tulis info SSH ke file txt di /root (workspace code-server)
cat > /root/ssh-info.txt << SSHINFO
============================================
  SSH CONNECTION INFO
============================================
  Host     : ${IP_ADDR}
  Port     : 22
  Username : root
  Password : ${SSH_PASS}

  Connect via terminal:
  ssh root@${IP_ADDR}

  code-server URL:
  http://${IP_ADDR}:6080
============================================
Generated at: $(date)
SSHINFO

# Tampilkan info di log
echo "============================================"
echo "  SERVER INFO"
echo "============================================"
echo "  [code-server]"
echo "  URL  : http://${IP_ADDR}:6080"
echo "  Auth : none"
echo ""
echo "  [SSH]"
echo "  Host : ${IP_ADDR}"
echo "  Port : 22"
echo "  User : root"
echo "  Pass : ${SSH_PASS}"
echo "============================================"
echo "  ssh-info.txt telah dibuat di /root"
echo "============================================"

# Start code-server
exec code-server --bind-addr 0.0.0.0:6080 --auth none /root
EOF

RUN chmod +x /entrypoint.sh

EXPOSE 6080 22

CMD ["/entrypoint.sh"]
