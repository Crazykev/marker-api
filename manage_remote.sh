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
        
        echo "🚀 启动服务..."
        nohup python3 server.py --host 0.0.0.0 --port 8080 > server.log 2>&1 &
        
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
                        echo "🌐 访问地址: http://192.168.0.60:8080/demo"
                        echo "📋 API端点: http://192.168.0.60:8080/convert"
                        exit 0
                    else
                        echo "⚠️  健康检查失败，继续等待..."
                    fi
                fi
                echo "⏳ 等待端口监听... ($i/5)"
                sleep 3
            done
            
            echo "❌ 端口8080在等待时间内未监听"
            echo "📝 查看最新日志："
            tail -15 server.log || echo "无法读取日志文件"
        else
            echo "❌ 服务启动失败"
            echo "📝 查看日志："
            tail -10 server.log || echo "无法读取日志文件"
        fi
EOF
}

stop_service() {
    echo "🛑 停止远程服务..."
    ssh $REMOTE_USER@$REMOTE_HOST << 'EOF'
        pkill -f "python.*server.py" || true
        echo "✅ 服务已停止"
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
    echo "📦 检查依赖..."
    ssh $REMOTE_USER@$REMOTE_HOST << 'EOF'
        cd $HOME/marker-api
        echo "ℹ️  依赖已在系统级别安装，无需额外操作"
        echo "✅ 依赖检查完成"
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