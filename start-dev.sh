#!/bin/bash

# Phase 5 - 本地开发环境启动脚本
# 用于启动 Docker 容器和验证系统

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 打印信息函数
print_header() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

# 检查 Docker 是否安装
check_docker() {
    print_header "检查 Docker 环境"
    
    if ! command -v docker &> /dev/null; then
        print_error "Docker 未安装"
        exit 1
    fi
    
    print_success "Docker 已安装: $(docker --version)"
    
    if ! command -v docker-compose &> /dev/null; then
        print_error "Docker Compose 未安装"
        exit 1
    fi
    
    print_success "Docker Compose 已安装: $(docker-compose --version)"
}

# 启动容器
start_containers() {
    print_header "启动 Docker 容器"
    
    echo "构建并启动所有服务..."
    docker-compose up -d
    
    if [ $? -eq 0 ]; then
        print_success "所有容器已启动"
    else
        print_error "启动容器失败"
        exit 1
    fi
}

# 等待服务就绪
wait_for_services() {
    print_header "等待服务就绪"
    
    # 检查 RabbitMQ
    echo -n "等待 RabbitMQ..."
    for i in {1..30}; do
        if docker exec meshflow-rabbitmq rabbitmq-diagnostics -q ping > /dev/null 2>&1; then
            print_success "RabbitMQ 已就绪"
            break
        fi
        if [ $i -eq 30 ]; then
            print_error "RabbitMQ 启动超时"
            exit 1
        fi
        echo -n "."
        sleep 1
    done
    
    # 检查 Redis
    echo -n "等待 Redis..."
    for i in {1..30}; do
        if docker exec meshflow-redis redis-cli ping > /dev/null 2>&1; then
            print_success "Redis 已就绪"
            break
        fi
        if [ $i -eq 30 ]; then
            print_error "Redis 启动超时"
            exit 1
        fi
        echo -n "."
        sleep 1
    done
    
    # 检查 PostgreSQL Master
    echo -n "等待 PostgreSQL Master..."
    for i in {1..30}; do
        if docker exec meshflow-postgres-master pg_isready -U meshflow > /dev/null 2>&1; then
            print_success "PostgreSQL Master 已就绪"
            break
        fi
        if [ $i -eq 30 ]; then
            print_error "PostgreSQL Master 启动超时"
            exit 1
        fi
        echo -n "."
        sleep 1
    done
    
    # 检查 Prometheus
    echo -n "等待 Prometheus..."
    for i in {1..30}; do
        if curl -s http://localhost:9090/-/healthy > /dev/null 2>&1; then
            print_success "Prometheus 已就绪"
            break
        fi
        if [ $i -eq 30 ]; then
            print_warning "Prometheus 启动可能需要更多时间"
            break
        fi
        echo -n "."
        sleep 1
    done
}

# 验证系统状态
verify_system() {
    print_header "验证系统状态"
    
    echo "正在检查运行中的容器..."
    docker-compose ps
    
    echo ""
    echo "正在验证连接..."
    
    # 测试 RabbitMQ 连接
    echo -n "  RabbitMQ (5672)..."
    if timeout 5 bash -c "echo > /dev/tcp/localhost/5672" 2>/dev/null; then
        print_success "RabbitMQ 可访问"
    else
        print_warning "RabbitMQ 不可访问"
    fi
    
    # 测试 Redis 连接
    echo -n "  Redis (6379)..."
    if timeout 5 bash -c "echo > /dev/tcp/localhost/6379" 2>/dev/null; then
        print_success "Redis 可访问"
    else
        print_warning "Redis 不可访问"
    fi
    
    # 测试 PostgreSQL 连接
    echo -n "  PostgreSQL Master (5432)..."
    if timeout 5 bash -c "echo > /dev/tcp/localhost/5432" 2>/dev/null; then
        print_success "PostgreSQL 可访问"
    else
        print_warning "PostgreSQL 不可访问"
    fi
    
    # 测试 Prometheus 连接
    echo -n "  Prometheus (9090)..."
    if curl -s http://localhost:9090/-/healthy > /dev/null 2>&1; then
        print_success "Prometheus 可访问"
    else
        print_warning "Prometheus 不可访问"
    fi
    
    # 测试 Grafana 连接
    echo -n "  Grafana (3000)..."
    if timeout 5 bash -c "echo > /dev/tcp/localhost/3000" 2>/dev/null; then
        print_success "Grafana 可访问"
    else
        print_warning "Grafana 不可访问"
    fi
    
    # 测试 Jaeger 连接
    echo -n "  Jaeger (16686)..."
    if timeout 5 bash -c "echo > /dev/tcp/localhost/16686" 2>/dev/null; then
        print_success "Jaeger 可访问"
    else
        print_warning "Jaeger 不可访问"
    fi
    
    # 测试 Kibana 连接
    echo -n "  Kibana (5601)..."
    if timeout 5 bash -c "echo > /dev/tcp/localhost/5601" 2>/dev/null; then
        print_success "Kibana 可访问"
    else
        print_warning "Kibana 不可访问"
    fi
}

# 显示访问信息
show_access_info() {
    print_header "服务访问信息"
    
    cat << EOF
${BLUE}消息队列${NC}
  RabbitMQ AMQP:     amqp://guest:guest@localhost:5672/
  RabbitMQ 管理界面:  http://localhost:15672 (guest/guest)

${BLUE}缓存${NC}
  Redis:             redis://localhost:6379

${BLUE}数据库${NC}
  PostgreSQL Master:  postgresql://meshflow:meshflow_password@localhost:5432/meshflow
  PostgreSQL Slave:   postgresql://meshflow:meshflow_password@localhost:5433/meshflow

${BLUE}监控和日志${NC}
  Prometheus:        http://localhost:9090
  Grafana:           http://localhost:3000 (admin/admin)
  Jaeger:            http://localhost:16686
  Kibana:            http://localhost:5601

${BLUE}负载均衡${NC}
  Nginx:             http://localhost:8080

${BLUE}API 端点${NC}
  API 服务器:        http://localhost:8000
  健康检查:          http://localhost:8000/health
EOF
}

# Python 验证 (如果需要)
verify_python() {
    if [ "$1" == "python" ]; then
        print_header "Python 环境验证"
        
        if ! command -v python3 &> /dev/null; then
            print_warning "Python3 未安装,跳过 Python 测试"
            return
        fi
        
        print_success "Python 已安装: $(python3 --version)"
        
        # 检查是否可导入 distributed_config
        if python3 -c "import sys; sys.path.insert(0, './meshflow_server'); from distributed_config import get_distributed_config" 2>/dev/null; then
            print_success "distributed_config 可导入"
        else
            print_warning "distributed_config 导入失败 (需要 pika 依赖)"
        fi
    fi
}

# 停止容器 (如果指定 stop)
stop_containers() {
    print_header "停止 Docker 容器"
    
    echo "停止所有服务..."
    docker-compose down
    
    if [ $? -eq 0 ]; then
        print_success "所有容器已停止"
    else
        print_error "停止容器失败"
        exit 1
    fi
}

# 查看日志
show_logs() {
    print_header "最近的日志"
    
    echo "选择要查看的服务日志:"
    echo "1) RabbitMQ"
    echo "2) Redis"
    echo "3) PostgreSQL Master"
    echo "4) Prometheus"
    echo "5) Grafana"
    echo "6) 所有日志"
    
    read -p "选择 (1-6): " choice
    
    case $choice in
        1) docker-compose logs rabbitmq ;;
        2) docker-compose logs redis ;;
        3) docker-compose logs postgres-master ;;
        4) docker-compose logs prometheus ;;
        5) docker-compose logs grafana ;;
        6) docker-compose logs ;;
        *) print_error "无效选择" ;;
    esac
}

# 主函数
main() {
    case "${1:-start}" in
        start)
            check_docker
            start_containers
            wait_for_services
            verify_system
            show_access_info
            verify_python python
            echo ""
            print_success "开发环境已启动! 所有服务就绪。"
            ;;
        stop)
            stop_containers
            ;;
        status)
            print_header "容器状态"
            docker-compose ps
            ;;
        logs)
            show_logs
            ;;
        restart)
            stop_containers
            sleep 2
            start_containers
            wait_for_services
            verify_system
            echo ""
            print_success "开发环境已重启!"
            ;;
        clean)
            print_header "清理所有容器和数据"
            read -p "确认删除所有容器和数据卷? (y/N): " confirm
            if [ "$confirm" = "y" ]; then
                docker-compose down -v
                print_success "已清理所有容器和数据卷"
            else
                print_warning "取消操作"
            fi
            ;;
        *)
            echo "Phase 5 开发环境启动脚本"
            echo ""
            echo "用法: $0 [命令]"
            echo ""
            echo "命令:"
            echo "  start      - 启动所有服务 (默认)"
            echo "  stop       - 停止所有服务"
            echo "  status     - 显示容器状态"
            echo "  logs       - 查看服务日志"
            echo "  restart    - 重启所有服务"
            echo "  clean      - 清理所有容器和数据"
            echo ""
            echo "示例:"
            echo "  ./start-dev.sh start"
            echo "  ./start-dev.sh stop"
            echo "  ./start-dev.sh logs"
            ;;
    esac
}

# 运行主函数
main "$@"
