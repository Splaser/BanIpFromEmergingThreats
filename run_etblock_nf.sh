#!/bin/bash
set -e

echo "[*] 检查 nftables 支持..."
command -v nft >/dev/null || { echo "[✘] nft 命令未安装，退出。"; exit 1; }

echo "[*] 下载 EmergingThreats 黑名单..."
wget -q --tries=3 --timeout=10 https://rules.emergingthreats.net/blockrules/compromised-ips.txt -O /tmp/etblock.txt
if [ $? -ne 0 ]; then
    echo "[✘] 下载失败，请检查网络。"
    exit 1
fi

# 检查是否是HTML
if grep -q '<!DOCTYPE html>' /tmp/etblock.txt; then
    echo "[✘] 下载内容错误，可能被墙或链接失效。"
    exit 1
fi

echo "[*] 创建 nftables 表/链/set..."

# 创建 inet filter 表（如果不存在）
nft list table inet filter >/dev/null 2>&1 || nft add table inet filter

# 创建 chain（注意 \; 的转义）
nft list chain inet filter output >/dev/null 2>&1 || \
nft add chain inet filter output '{ type filter hook output priority 0; policy accept; }'

nft list chain inet filter forward >/dev/null 2>&1 || \
nft add chain inet filter forward '{ type filter hook forward priority 0; policy accept; }'

nft list chain inet filter input >/dev/null 2>&1 || \
nft add chain inet filter input '{ type filter hook input priority 0; policy accept; }'

# 创建 etblock set（如已存在则清空）
if nft list set inet filter etblock >/dev/null 2>&1; then
    echo "[*] Set 已存在，清空旧规则..."
    nft flush set inet filter etblock
else
    nft add set inet filter etblock '{ type ipv4_addr; flags interval; }'
fi

# 写入 IP
echo "[*] 加载 IP 到 nft set..."

grep -Ev '^(#|$)' /tmp/etblock.txt | while read ip; do
    [[ -z "$ip" ]] && continue
    nft add element inet filter etblock { $ip }
done

# 添加拦截规则（如未存在则添加）
nft list chain inet filter output | grep -q '@etblock' || \
nft insert rule inet filter output ip daddr @etblock drop

nft list chain inet filter forward | grep -q '@etblock' || \
nft insert rule inet filter forward ip daddr @etblock drop

nft list chain inet filter input | grep -q '@etblock' || \
nft insert rule inet filter input ip saddr @etblock drop

# 输出统计
count=$(nft list set inet filter etblock | grep -cE '^\s*[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+')
echo "[✔] 成功加载 $count 个 IP 至 nftables etblock 集合。"

nft list ruleset > /etc/nftables.conf

rm -f /tmp/etblock.txt /tmp/etblock.nft

systemctl enable nftables