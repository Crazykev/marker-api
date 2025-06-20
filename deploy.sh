#!/bin/bash

# 自动化部署脚本 - 将本地修改部署到远程测试机
# 使用方法: ./deploy.sh [commit_message]

set -e  # 遇到错误立即退出

# 配置变量
REMOTE_HOST="192.168.0.60"
REMOTE_USER="crazykev"  # 根据实际用户名修改
REMOTE_PATH="$HOME/marker-api"
REMOTE_BRANCH="update-marker"  # 当前分支名
COMMIT_MESSAGE="${1:-Auto deploy: $(date '+%Y-%m-%d %H:%M:%S')}"

echo "🚀 开始自动化部署..."
echo "📝 提交信息: $COMMIT_MESSAGE"
echo "🎯 目标主机: $REMOTE_HOST"
echo "📁 远程路径: $REMOTE_PATH"
echo

# 步骤1: 检查是否有未提交的更改
echo "🔍 检查本地更改..."
if [ -n "$(git status --porcelain)" ]; then
    echo "📦 发现未提交的更改，正在提交..."
    git add .
    git commit -m "$COMMIT_MESSAGE"
    echo "✅ 本地提交完成"
else
    echo "✅ 没有新的更改需要提交"
fi

# 步骤2: 推送到远程仓库
echo
echo "📤 推送到GitHub远程仓库..."
git push custom $REMOTE_BRANCH
echo "✅ 推送完成"

# 步骤3: 连接到远程主机并执行部署
echo
echo "🔗 连接到远程主机并执行部署..."

# 首先尝试Git拉取，如果失败则使用SCP备份方案
echo "🔄 尝试Git拉取最新代码..."
if ! ssh $REMOTE_USER@$REMOTE_HOST << 'EOF'
    cd $HOME/marker-api
    echo "📍 当前在远程主机: $(hostname)"
    echo "🔄 拉取最新代码..."
    timeout 30 git fetch origin && timeout 30 git pull origin update-marker
EOF
then
    echo "⚠️  Git拉取失败，使用SCP备份方案..."
    echo "📤 复制关键文件到远程主机..."
    scp server.py $REMOTE_USER@$REMOTE_HOST:~/marker-api/
    scp marker_api/demo.py $REMOTE_USER@$REMOTE_HOST:~/marker-api/marker_api/
    echo "✅ 文件复制完成"
fi

# 执行部署和启动
ssh $REMOTE_USER@$REMOTE_HOST << 'EOF'
    set -e
    
    echo "📁 切换到项目目录..."
    cd $HOME/marker-api
    
    echo "📦 检查并安装依赖..."
    # 检查是否存在虚拟环境
    if [ ! -d "venv" ]; then
        echo "🔧 创建虚拟环境..."
        python3 -m venv venv
    fi
    
    # 激活虚拟环境并安装依赖
    source venv/bin/activate
    if [ -f "pyproject.toml" ]; then
        echo "📋 安装项目依赖..."
        pip install -e . || echo "⚠️ 依赖安装警告，继续执行..."
    fi
    
    # 停止现有服务（如果存在）
    echo "🛑 停止现有服务..."
    pkill -f "python.*server.py" || true
    pkill -f "python3.*server.py" || true
    sleep 3
    
    echo "✅ 部署完成！"
    echo "🎯 准备启动服务..."
EOF

echo
echo "🚀 启动远程服务..."
# 在后台启动服务并进行智能验证
ssh $REMOTE_USER@$REMOTE_HOST << 'EOF'
    cd $HOME/marker-api
    
    # 确保激活虚拟环境
    if [ -d "venv" ]; then
        source venv/bin/activate
    fi
    
    # 启动服务
    echo "🚀 启动服务器..."
    nohup python3 server.py --host 0.0.0.0 --port 8080 > server.log 2>&1 &
    SERVER_PID=$!
    
    echo "⏳ 等待服务启动..."
    # 智能等待服务启动（最多等待30秒）
    for i in {1..30}; do
        sleep 1
        if pgrep -f "python3.*server.py" > /dev/null; then
            # 检查端口是否监听
            if netstat -tlnp 2>/dev/null | grep -q ":8080.*LISTEN"; then
                # 测试健康检查端点
                if curl -s http://127.0.0.1:8080/health | grep -q "Welcome to Marker-api"; then
                    echo "✅ 服务启动成功！($i 秒)"
                    break
                fi
            fi
        fi
        
        if [ $i -eq 30 ]; then
            echo "❌ 服务启动超时"
            echo "📝 最近日志:"
            tail -10 server.log 2>/dev/null || echo "无法读取日志文件"
            exit 1
        fi
        
        printf "."
    done
    
    echo
    echo "📊 最终状态检查..."
    if pgrep -f "python3.*server.py" > /dev/null; then
        echo "✅ 服务进程正在运行 (PID: $(pgrep -f 'python3.*server.py'))"
        echo "✅ 端口监听状态: $(netstat -tlnp 2>/dev/null | grep ':8080.*LISTEN' || echo '未检测到')"
        
        # 测试各个端点
        echo "🧪 测试服务端点..."
        if curl -s http://127.0.0.1:8080/health > /dev/null; then
            echo "✅ /health 端点正常"
        else
            echo "⚠️  /health 端点异常"
        fi
        
        echo
        echo "🎉 部署成功完成！"
        echo "🌐 前端访问: http://192.168.0.60:8080/demo"
        echo "📋 API端点: http://192.168.0.60:8080/convert"
        echo "📋 健康检查: http://192.168.0.60:8080/health"
        echo "📝 日志文件: $HOME/marker-api/server.log"
        echo "🔍 查看日志: tail -f ~/marker-api/server.log"
    else
        echo "❌ 服务启动失败"
        echo "📝 错误日志:"
        tail -20 server.log 2>/dev/null || echo "无法读取日志文件"
        exit 1
    fi
EOF

echo
echo "🎉 部署完成！"
echo "🌐 前端访问: http://192.168.0.60:8080/demo"
echo "📋 API访问: http://192.168.0.60:8080/convert"
echo "📝 查看日志: ssh $REMOTE_USER@$REMOTE_HOST 'tail -f $HOME/marker-api/server.log'"
echo
echo "🔧 其他有用命令:"
echo "   查看服务状态: ssh $REMOTE_USER@$REMOTE_HOST 'pgrep -f python.*server.py'"
echo "   停止服务: ssh $REMOTE_USER@$REMOTE_HOST 'pkill -f python.*server.py'"
echo "   重启服务: ./deploy.sh" 