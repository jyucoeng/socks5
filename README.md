# 项目说明
 socks5

## 老王的保活项目
- 老王[仓库地址](https://github.com/eooce/Sing-box)  
> 特点：全自动保活

----

## VPS版一键无交互脚本Socks5  安装/卸载脚本 (同时支持 IPv4 和 IPv6)
用法
### 安装：
```
PORT=16805 USERNAME=用户名 PASSWORD=密码 bash <(curl -Ls https://raw.githubusercontent.com/jyucoeng/socks5/main/sock5.sh)
```
### 说明：IPv4 使用端口 PORT，IPv6 则使用端口 PORT+1

### 卸载:
```
bash <(curl -Ls https://raw.githubusercontent.com/jyucoeng/socks5/main/sock5.sh) uninstall
```
查看配置
```
cat /usr/local/sb/config.json
```
## 测试socks5是否通畅
运行以下命令，若正确返回服务器ip则节点通畅
```
curl ip.sb --socks5 用户名:密码@localhost:端口
```
或者
 打开下方网址验证

https://iplau.com/category/ip-detection-tool.html

# 🧩 NAT64 一键配置脚本

在仅 IPv6 的 VPS 上启用 NAT64，访问 IPv4 网站。

---

## ✅ 使用方法

### 1. 设置 DNS64

```bash
echo -e "nameserver 2606:4700:4700::64\nnameserver 2606:4700:4700::6400" | sudo tee /etc/resolv.conf

```
---

### 2. 安装 NAT64 支持

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/jyucoeng/socks5/main/nat64-setup.sh)

```

🔍 验证是否成功

```bash
curl -6 http://example.com

```
能返回网页代码说明成功.

❌ 卸载方法

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/jyucoeng/socks5/main/nat64-setup.sh) uninstall

```
📌 说明
	•	默认 NAT64 地址为 2001:67c:2960:6464::
	•	默认网卡为 venet0，如不同请自行修改脚本

---


