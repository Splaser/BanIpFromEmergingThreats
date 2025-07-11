#!/bin/bash

# ========== 初始化 ========== #
echo "[*] 初始化 etblock ipset 规则..."

ipset list etblock >/dev/null 2>&1
if [ $? -ne 0 ]; then
    ipset create etblock hash:ip
else
    ipset flush etblock
fi

# ========== 下载 ET Block 列表 ========== #
echo "[*] 正在下载 EmergingThreats 黑名单..."
wget -q https://rules.emergingthreats.net/blockrules/compromised-ips.txt -O /tmp/etblock.txt

if [ $? -ne 0 ]; then
    echo "[✘] 下载失败，请检查网络。"
    exit 1
fi

# ========== 加入 ipset ========== #
echo "[*] 加载 IP 至 ipset..."
while read ip; do
    [[ "$ip" =~ ^#.*$ || -z "$ip" ]] && continue
    ipset add etblock "$ip" 2>/dev/null
done < /tmp/etblock.txt

# ========== 设置 iptables 拦截规则 ========== #
# 防止重复插入规则
iptables -C OUTPUT -m set --match-set etblock dst -j DROP 2>/dev/null || \
iptables -I OUTPUT -m set --match-set etblock dst -j DROP

iptables -C FORWARD -m set --match-set etblock dst -j DROP 2>/dev/null || \
iptables -I FORWARD -m set --match-set etblock dst -j DROP

# ========== 完成提示 ========== #
count=$(ipset list etblock | grep -c '^1')
echo "[✔] 加载完成，共添加 $count 个封锁 IP。"
