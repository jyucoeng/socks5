# 项目说明
 socks5

----

## VPS版一键无交互脚本Socks5  安装/卸载脚本 (同时支持 IPv4 和 IPv6)
用法
### 安装：
```
PORT=端口号 USERNAME=用户名 PASSWORD=密码 bash <(curl -Ls https://raw.githubusercontent.com/jyucoeng/socks5/refs/heads/main/socks5.sh)
```

### 卸载:
```
bash <(curl -Ls https://raw.githubusercontent.com/jyucoeng/socks5/refs/heads/main/socks5.sh) uninstall
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

