wget https://raw.githubusercontent.com/luptnn/probe/refs/heads/main/pb.sh \
chmod +x pb.sh \
./pb.sh


alpine:
apk add procps iproute2 coreutils

fail2ban install
wget https://raw.githubusercontent.com/luptnn/probe/refs/heads/main/install-fail2ban.sh

chmod +x install-fail2ban.sh

bash install-fail2ban.sh
