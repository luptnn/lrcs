一、probe install

wget https://raw.githubusercontent.com/luptnn/lrcs/refs/heads/main/pb.sh \
chmod +x pb.sh \
./pb.sh

alpine:
apk add procps iproute2 coreutils

二、fail2ban install

wget https://raw.githubusercontent.com/luptnn/lrcs/refs/heads/main/install-fail2ban.sh

#使用 sed 快速修复执行命令直接删掉脚本中的 Windows 换行符：

sed -i 's/\r$//' install-fail2ban.sh

chmod +x install-fail2ban.sh

./install-fail2ban.sh
