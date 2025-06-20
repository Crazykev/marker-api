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
ssh $REMOTE_USER@$REMOTE_HOST << 'EOF'
    set -e
    
    echo "📍 当前在远程主机: $(hostname)"
    echo "📁 切换到项目目录..."
    cd $HOME/marker-api
    
    echo "🔄 拉取最新代码..."
    git fetch origin
    git checkout update-marker
    git pull origin update-marker
        
    # 安装依赖
    if [ -f "pyproject.toml" ]; then
        echo "📋 安装项目依赖..."
        pip install -e .
    fi
    
    # 停止现有服务（如果存在）
    echo "🛑 停止现有服务..."
    pkill -f "python.*server.py" || true
    sleep 2
    
    echo "✅ 部署完成！"
    echo "🎯 准备启动服务..."
EOF

echo
echo "🚀 启动远程服务..."
# 在后台启动服务
ssh $REMOTE_USER@$REMOTE_HOST << 'EOF'
    cd $HOME/marker-api
    source venv/bin/activate
    nohup python server.py --host 0.0.0.0 --port 8080 > server.log 2>&1 &
    echo "✅ 服务已在后台启动"
    echo "📊 服务状态检查..."
    sleep 3
    if pgrep -f "python.*server.py" > /dev/null; then
        echo "✅ 服务运行正常"
        echo "🌐 访问地址: http://192.168.0.60:8080/demo"
        echo "📋 API端点: http://192.168.0.60:8080/convert"
        echo "📝 日志文件: $HOME/marker-api/server.log"
    else
        echo "❌ 服务启动失败，请检查日志"
        tail -20 server.log
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