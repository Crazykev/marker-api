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
    
    echo "🛑 停止现有服务..."
    pkill -f "python.*server.py" || true
    sleep 3
    
    echo "🚀 启动服务（CPU模式）..."
    nohup TORCH_DEVICE=cpu python3 server.py --host 0.0.0.0 --port 8080 > server.log 2>&1 &
    
    echo "⏳ 等待服务启动（模型加载需要时间）..."
    sleep 15
    
    # 验证服务启动
    if pgrep -f "python.*server.py" > /dev/null; then
        echo "✅ 服务进程已启动"
        
        # 等待端口监听，最多重试5次
        echo "🔍 检查端口监听状态..."
        for i in {1..5}; do
            if netstat -tlnp 2>/dev/null | grep -q ":8080.*LISTEN"; then
                echo "✅ 端口8080正在监听"
                
                # 测试健康检查端点
                sleep 2
                if curl -s --max-time 10 http://127.0.0.1:8080/health | grep -q "Welcome to Marker-api"; then
                    echo "✅ 健康检查通过"
                    echo "🎉 服务启动成功！"
                    break
                else
                    echo "⚠️  健康检查失败，继续等待..."
                fi
            fi
            echo "⏳ 等待端口监听... ($i/5)"
            sleep 3
        done
        
        # 最终状态检查
        if netstat -tlnp 2>/dev/null | grep -q ":8080.*LISTEN"; then
            echo "✅ 最终状态：服务正在运行"
        else
            echo "❌ 最终状态：端口8080未监听"
            echo "📝 查看最新日志："
            tail -15 server.log || echo "无法读取日志文件"
        fi
    else
        echo "❌ 服务启动失败"
        echo "📝 查看日志："
        tail -10 server.log || echo "无法读取日志文件"
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