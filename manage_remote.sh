#!/bin/bash

# 远程服务管理脚本
# 使用方法: ./manage_remote.sh [command]

REMOTE_HOST="192.168.0.60"
REMOTE_USER="crazykev"
REMOTE_PATH="$HOME/marker-api"

usage() {
    echo "🔧 远程服务管理工具"
    echo "使用方法: ./manage_remote.sh [command]"
    echo
    echo "可用命令:"
    echo "  deploy    - 完整部署（提交、推送、拉取、安装、启动）"
    echo "  start     - 启动服务"
    echo "  stop      - 停止服务"
    echo "  restart   - 重启服务"
    echo "  status    - 查看服务状态"
    echo "  logs      - 查看服务日志"
    echo "  shell     - 连接到远程主机"
    echo "  pull      - 仅拉取最新代码"
    echo "  install   - 仅安装依赖"
    echo
    echo "示例:"
    echo "  ./manage_remote.sh deploy"
    echo "  ./manage_remote.sh logs"
    echo "  ./manage_remote.sh restart"
}

deploy() {
    echo "🚀 执行完整部署..."
    ./deploy.sh "$@"
}

start_service() {
    echo "🚀 启动远程服务..."
    ssh $REMOTE_USER@$REMOTE_HOST << 'EOF'
        cd $HOME/marker-api
        
        # 确保激活虚拟环境
        if [ -d "venv" ]; then
            source venv/bin/activate
        fi
        
        # 启动服务
        nohup python3 server.py --host 0.0.0.0 --port 8080 > server.log 2>&1 &
        
        echo "⏳ 等待服务启动..."
        # 智能等待服务启动（最多等待20秒）
        for i in {1..20}; do
            sleep 1
            if pgrep -f "python3.*server.py" > /dev/null; then
                if netstat -tlnp 2>/dev/null | grep -q ":8080.*LISTEN"; then
                    if curl -s http://127.0.0.1:8080/health | grep -q "Welcome to Marker-api"; then
                        echo "✅ 服务启动成功！($i 秒)"
                        echo "🌐 访问地址: http://192.168.0.60:8080/demo"
                        echo "📋 API端点: http://192.168.0.60:8080/convert"
                        return 0
                    fi
                fi
            fi
            printf "."
        done
        
        echo
        echo "❌ 服务启动失败或超时"
        echo "📝 最近日志:"
        tail -10 server.log 2>/dev/null || echo "无法读取日志文件"
EOF
}

stop_service() {
    echo "🛑 停止远程服务..."
    ssh $REMOTE_USER@$REMOTE_HOST << 'EOF'
        pkill -f "python.*server.py" || true
        pkill -f "python3.*server.py" || true
        sleep 2
        
        # 确认服务已停止
        if pgrep -f "python3.*server.py" > /dev/null; then
            echo "⚠️  服务仍在运行，强制终止..."
            pkill -9 -f "python3.*server.py" || true
            sleep 1
        fi
        
        if ! pgrep -f "python3.*server.py" > /dev/null; then
            echo "✅ 服务已停止"
        else
            echo "❌ 服务停止失败"
        fi
EOF
}

restart_service() {
    echo "🔄 重启远程服务..."
    stop_service
    sleep 2
    start_service
}

check_status() {
    echo "📊 检查服务状态..."
    ssh $REMOTE_USER@$REMOTE_HOST << 'EOF'
        if pgrep -f "python.*server.py" > /dev/null; then
            echo "✅ 服务正在运行"
            echo "🔍 进程信息:"
            pgrep -f "python.*server.py" | head -5
            echo "🌐 访问地址: http://192.168.0.60:8080/demo"
            echo "📋 API端点: http://192.168.0.60:8080/convert"
        else
            echo "❌ 服务未运行"
        fi
EOF
}

show_logs() {
    echo "📝 查看服务日志..."
    ssh $REMOTE_USER@$REMOTE_HOST "tail -f $HOME/marker-api/server.log"
}

connect_shell() {
    echo "🔗 连接到远程主机..."
    ssh $REMOTE_USER@$REMOTE_HOST
}

pull_code() {
    echo "🔄 拉取最新代码..."
    ssh $REMOTE_USER@$REMOTE_HOST << 'EOF'
        cd $HOME/marker-api
        git fetch origin
        git pull origin update-marker
        echo "✅ 代码更新完成"
EOF
}

install_deps() {
    echo "📦 安装依赖..."
    ssh $REMOTE_USER@$REMOTE_HOST << 'EOF'
        cd $HOME/marker-api
        if [ ! -d "venv" ]; then
            python3 -m venv venv
        fi
        source venv/bin/activate
        if [ -f "pyproject.toml" ]; then
            pip install -e .
        fi
        echo "✅ 依赖安装完成"
EOF
}

# 主逻辑
case "${1:-help}" in
    deploy)
        deploy "${@:2}"
        ;;
    start)
        start_service
        ;;
    stop)
        stop_service
        ;;
    restart)
        restart_service
        ;;
    status)
        check_status
        ;;
    logs)
        show_logs
        ;;
    shell)
        connect_shell
        ;;
    pull)
        pull_code
        ;;
    install)
        install_deps
        ;;
    help|--help|-h)
        usage
        ;;
    *)
        echo "❌ 未知命令: $1"
        echo
        usage
        exit 1
        ;;
esac 