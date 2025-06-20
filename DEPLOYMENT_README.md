# 自动化部署指南

本文档说明如何使用自动化脚本将 marker-api 部署到远程测试机 `192.168.0.60`。

## 🛠️ 脚本说明

### 1. `deploy.sh` - 完整部署脚本
自动执行完整的部署流程：提交代码 → 推送到GitHub → 远程拉取 → 安装依赖 → 启动服务

### 2. `manage_remote.sh` - 远程服务管理脚本
提供各种远程服务管理功能的快捷命令

## 🚀 使用方法

### 首次部署
```bash
# 执行完整部署（包含自定义提交信息）
./deploy.sh "修复PDF上传404错误"

# 或使用默认提交信息
./deploy.sh
```

### 日常管理

```bash
# 查看帮助
./manage_remote.sh help

# 快速部署（与 deploy.sh 相同）
./manage_remote.sh deploy

# 启动服务
./manage_remote.sh start

# 停止服务
./manage_remote.sh stop

# 重启服务
./manage_remote.sh restart

# 查看服务状态
./manage_remote.sh status

# 查看实时日志
./manage_remote.sh logs

# 连接到远程主机
./manage_remote.sh shell

# 仅拉取最新代码
./manage_remote.sh pull

# 仅安装依赖
./manage_remote.sh install
```

## 🔧 配置说明

### 远程主机配置
- **主机地址**: `192.168.0.60`
- **用户名**: `crazykev`
- **项目路径**: `$HOME/marker-api`
- **分支**: `update-marker`

### 服务配置
- **端口**: `8080`
- **前端访问**: `http://192.168.0.60:8080/demo`
- **API端点**: `http://192.168.0.60:8080/convert`
- **日志文件**: `$HOME/marker-api/server.log`

## 📋 部署流程

### `deploy.sh` 执行步骤：
1. 检查本地是否有未提交的更改
2. 如有更改，自动提交到本地仓库
3. 推送到GitHub远程仓库（custom origin）
4. SSH连接到远程主机
5. 在远程主机上拉取最新代码
6. 创建/激活虚拟环境
7. 安装项目依赖
8. 停止现有服务进程
9. 在后台启动新服务
10. 检查服务状态

## 🐛 故障排查

### 常见问题及解决方案

#### 1. SSH连接失败
```bash
# 检查SSH连接
ssh crazykev@192.168.0.60

# 确保SSH密钥已正确配置
ssh-add ~/.ssh/id_rsa
```

#### 2. 服务启动失败
```bash
# 查看服务日志
./manage_remote.sh logs

# 或直接SSH连接查看
ssh crazykev@192.168.0.60
cd ~/marker-api
tail -f server.log
```

#### 3. 依赖安装失败
```bash
# 重新安装依赖
./manage_remote.sh install

# 或手动安装
ssh crazykev@192.168.0.60
cd ~/marker-api
source venv/bin/activate
pip install -e .
```

#### 4. 端口占用
```bash
# 检查端口占用
ssh crazykev@192.168.0.60 "netstat -tulpn | grep 8080"

# 停止占用端口的进程
./manage_remote.sh stop
```

## 🔍 监控和维护

### 查看服务状态
```bash
# 快速状态检查
./manage_remote.sh status

# 详细进程信息
ssh crazykev@192.168.0.60 "ps aux | grep python"
```

### 日志管理
```bash
# 实时查看日志
./manage_remote.sh logs

# 查看最近的错误日志
ssh crazykev@192.168.0.60 "tail -n 50 ~/marker-api/server.log | grep -i error"
```

### 服务重启
```bash
# 优雅重启
./manage_remote.sh restart

# 强制重启（如果服务无响应）
ssh crazykev@192.168.0.60 "pkill -9 -f python.*server.py"
./manage_remote.sh start
```

## 📝 注意事项

1. **SSH密钥**: 确保本地已配置SSH密钥，可以无密码登录远程主机
2. **网络连接**: 确保本地可以访问 `192.168.0.60`
3. **Git配置**: 确保本地Git配置正确，可以推送到custom远程仓库
4. **Python环境**: 远程主机需要Python 3.10+环境
5. **权限问题**: 确保远程用户有权限安装Python包和启动服务

## 🎯 快速开始

```bash
# 1. 克隆仓库到本地（如果还没有）
git clone <your-repo-url> marker-api
cd marker-api

# 2. 首次部署
./deploy.sh "初始部署"

# 3. 检查服务状态
./manage_remote.sh status

# 4. 访问服务
# 浏览器打开: http://192.168.0.60:8080/demo
```

完成！🎉 