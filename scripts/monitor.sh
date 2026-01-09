#!/bin/bash
set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
TERRAFORM_DIR="$PROJECT_DIR/terraform"
CHECK_INTERVAL="${CHECK_INTERVAL:-30}"
MAX_RETRIES="${MAX_RETRIES:-5}"
RETRY_DELAY="${RETRY_DELAY:-10}"
AWS_REGION="${AWS_REGION:-us-east-1}"

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║         Book Library - Application Monitor                  ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Functions
print_status() { echo -e "${GREEN}[✓]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
print_error() { echo -e "${RED}[✗]${NC} $1"; }
print_info() { echo -e "${BLUE}[i]${NC} $1"; }

# Get instance details from Terraform
get_instance_info() {
    cd "$TERRAFORM_DIR"

    INSTANCE_ID=$(terraform output -raw instance_id 2>/dev/null || echo "")
    PUBLIC_IP=$(terraform output -raw instance_public_ip 2>/dev/null || echo "")
    APP_URL=$(terraform output -raw app_url 2>/dev/null || echo "")
    S3_BUCKET=$(terraform output -raw s3_app_bucket 2>/dev/null || echo "")
    KEY_PATH=$(terraform output -raw private_key_path 2>/dev/null || echo "")

    if [ -z "$INSTANCE_ID" ] || [ -z "$PUBLIC_IP" ]; then
        print_error "Could not retrieve instance information"
        print_info "Make sure the infrastructure is deployed"
        exit 1
    fi
}

# Check if application is responding
check_health() {
    local url="$1/health"
    local response

    response=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "$url" 2>/dev/null || echo "000")

    echo "$response"
}

# Check EC2 instance status
check_instance_status() {
    local status

    status=$(aws ec2 describe-instances \
        --instance-ids "$INSTANCE_ID" \
        --query 'Reservations[0].Instances[0].State.Name' \
        --output text \
        --region "$AWS_REGION" 2>/dev/null || echo "unknown")

    echo "$status"
}

# Check instance health via EC2
check_instance_health() {
    local status

    status=$(aws ec2 describe-instance-status \
        --instance-ids "$INSTANCE_ID" \
        --query 'InstanceStatuses[0].InstanceStatus.Status' \
        --output text \
        --region "$AWS_REGION" 2>/dev/null || echo "unknown")

    echo "$status"
}

# Restart the application service
restart_application() {
    print_info "Attempting to restart the application..."

    # Try SSM first
    COMMAND_ID=$(aws ssm send-command \
        --instance-ids "$INSTANCE_ID" \
        --document-name "AWS-RunShellScript" \
        --parameters commands=["sudo systemctl restart book-library && sudo systemctl restart nginx"] \
        --region "$AWS_REGION" \
        --query 'Command.CommandId' \
        --output text 2>/dev/null || echo "")

    if [ -n "$COMMAND_ID" ]; then
        print_info "SSM restart command sent: $COMMAND_ID"
        sleep 5
        return 0
    fi

    # Fallback to SSH
    if [ -f "$KEY_PATH" ]; then
        print_info "Trying SSH restart..."

        ssh -i "$KEY_PATH" -o StrictHostKeyChecking=no -o ConnectTimeout=10 ec2-user@"$PUBLIC_IP" \
            "sudo systemctl restart book-library && sudo systemctl restart nginx" 2>/dev/null

        if [ $? -eq 0 ]; then
            print_status "Application restarted via SSH"
            return 0
        fi
    fi

    print_warning "Could not restart application automatically"
    return 1
}

# Reboot the instance
reboot_instance() {
    print_warning "Rebooting EC2 instance..."

    aws ec2 reboot-instances \
        --instance-ids "$INSTANCE_ID" \
        --region "$AWS_REGION"

    print_info "Waiting for instance to come back online..."
    sleep 60

    # Wait for instance to be running
    for i in {1..12}; do
        status=$(check_instance_status)
        if [ "$status" = "running" ]; then
            print_status "Instance is running"
            break
        fi
        sleep 10
    done
}

# Redeploy application
redeploy_application() {
    print_info "Redeploying application from S3..."

    COMMAND_ID=$(aws ssm send-command \
        --instance-ids "$INSTANCE_ID" \
        --document-name "AWS-RunShellScript" \
        --parameters commands=["cd /opt/book-library && aws s3 cp s3://$S3_BUCKET/application.zip . --region $AWS_REGION && unzip -o application.zip && sudo systemctl restart book-library"] \
        --region "$AWS_REGION" \
        --query 'Command.CommandId' \
        --output text 2>/dev/null || echo "")

    if [ -n "$COMMAND_ID" ]; then
        print_info "Redeploy command sent: $COMMAND_ID"
        sleep 30
        return 0
    fi

    # Fallback to SSH
    if [ -f "$KEY_PATH" ]; then
        ssh -i "$KEY_PATH" -o StrictHostKeyChecking=no ec2-user@"$PUBLIC_IP" << ENDSSH
            cd /opt/book-library
            aws s3 cp s3://$S3_BUCKET/application.zip . --region $AWS_REGION
            unzip -o application.zip
            sudo systemctl restart book-library
ENDSSH
        return 0
    fi

    return 1
}

# Main monitoring function
monitor_application() {
    get_instance_info

    echo -e "\n${BLUE}Monitoring Configuration:${NC}"
    echo "  Instance ID:     $INSTANCE_ID"
    echo "  Public IP:       $PUBLIC_IP"
    echo "  Application URL: $APP_URL"
    echo "  Check Interval:  ${CHECK_INTERVAL}s"
    echo ""

    local consecutive_failures=0
    local recovery_attempts=0

    while true; do
        local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

        # Check instance status
        local instance_status=$(check_instance_status)

        if [ "$instance_status" != "running" ]; then
            print_error "[$timestamp] Instance is not running (status: $instance_status)"

            if [ "$instance_status" = "stopped" ]; then
                print_info "Starting stopped instance..."
                aws ec2 start-instances --instance-ids "$INSTANCE_ID" --region "$AWS_REGION"
                sleep 60
            fi

            consecutive_failures=$((consecutive_failures + 1))
        else
            # Check application health
            local http_status=$(check_health "$APP_URL")

            if [ "$http_status" = "200" ]; then
                print_status "[$timestamp] Application healthy (HTTP $http_status)"
                consecutive_failures=0
                recovery_attempts=0
            else
                consecutive_failures=$((consecutive_failures + 1))
                print_error "[$timestamp] Application unhealthy (HTTP $http_status) - Failure #$consecutive_failures"

                # Recovery logic
                if [ $consecutive_failures -ge 2 ]; then
                    recovery_attempts=$((recovery_attempts + 1))

                    case $recovery_attempts in
                        1)
                            print_warning "Attempting recovery: Restart application service"
                            restart_application
                            sleep 30
                            ;;
                        2)
                            print_warning "Attempting recovery: Redeploy application"
                            redeploy_application
                            sleep 60
                            ;;
                        3)
                            print_warning "Attempting recovery: Reboot instance"
                            reboot_instance
                            sleep 120
                            ;;
                        *)
                            print_error "Maximum recovery attempts reached"
                            print_info "Manual intervention may be required"
                            recovery_attempts=0
                            ;;
                    esac
                fi
            fi
        fi

        sleep "$CHECK_INTERVAL"
    done
}

# Single health check
single_check() {
    get_instance_info

    echo -e "\n${BLUE}Performing health check...${NC}\n"

    # EC2 Instance Status
    local instance_status=$(check_instance_status)
    if [ "$instance_status" = "running" ]; then
        print_status "EC2 Instance: running"
    else
        print_error "EC2 Instance: $instance_status"
    fi

    # Instance Health
    local health_status=$(check_instance_health)
    if [ "$health_status" = "ok" ]; then
        print_status "Instance Health: ok"
    else
        print_warning "Instance Health: $health_status"
    fi

    # Application Health
    local http_status=$(check_health "$APP_URL")
    if [ "$http_status" = "200" ]; then
        print_status "Application: healthy (HTTP $http_status)"
    else
        print_error "Application: unhealthy (HTTP $http_status)"
    fi

    # Get application response time
    local response_time=$(curl -s -o /dev/null -w "%{time_total}" --connect-timeout 5 "$APP_URL" 2>/dev/null || echo "N/A")
    print_info "Response Time: ${response_time}s"

    echo ""
    echo "Application URL: $APP_URL"
    echo ""
}

# Wait for application to become available
wait_for_ready() {
    get_instance_info

    echo -e "\n${BLUE}Waiting for application to become available...${NC}\n"

    local attempts=0

    while [ $attempts -lt $MAX_RETRIES ]; do
        attempts=$((attempts + 1))

        local http_status=$(check_health "$APP_URL")

        if [ "$http_status" = "200" ]; then
            print_status "Application is ready!"
            echo ""
            echo "  URL: $APP_URL"
            echo ""
            return 0
        fi

        print_info "Attempt $attempts/$MAX_RETRIES - HTTP status: $http_status"
        sleep "$RETRY_DELAY"
    done

    print_error "Application did not become available within the timeout period"
    return 1
}

# Fix application issues
fix_issues() {
    get_instance_info

    echo -e "\n${BLUE}Attempting to fix application issues...${NC}\n"

    # Step 1: Check instance status
    print_info "Step 1: Checking instance status..."
    local instance_status=$(check_instance_status)

    if [ "$instance_status" = "stopped" ]; then
        print_warning "Instance is stopped. Starting..."
        aws ec2 start-instances --instance-ids "$INSTANCE_ID" --region "$AWS_REGION"
        print_info "Waiting for instance to start..."
        sleep 60
    elif [ "$instance_status" != "running" ]; then
        print_error "Instance in unexpected state: $instance_status"
        return 1
    fi

    print_status "Instance is running"

    # Step 2: Check application health
    print_info "Step 2: Checking application health..."
    local http_status=$(check_health "$APP_URL")

    if [ "$http_status" = "200" ]; then
        print_status "Application is already healthy!"
        return 0
    fi

    # Step 3: Restart application
    print_info "Step 3: Restarting application service..."
    restart_application
    sleep 15

    http_status=$(check_health "$APP_URL")
    if [ "$http_status" = "200" ]; then
        print_status "Application recovered after restart!"
        return 0
    fi

    # Step 4: Redeploy application
    print_info "Step 4: Redeploying application from S3..."
    redeploy_application
    sleep 30

    http_status=$(check_health "$APP_URL")
    if [ "$http_status" = "200" ]; then
        print_status "Application recovered after redeploy!"
        return 0
    fi

    # Step 5: Reboot instance
    print_info "Step 5: Rebooting instance..."
    reboot_instance
    sleep 60

    http_status=$(check_health "$APP_URL")
    if [ "$http_status" = "200" ]; then
        print_status "Application recovered after reboot!"
        return 0
    fi

    print_error "Could not automatically fix the application"
    print_info "Manual investigation may be required"
    return 1
}

# Main
case "${1:-check}" in
    check)
        single_check
        ;;
    wait)
        wait_for_ready
        ;;
    fix)
        fix_issues
        ;;
    monitor)
        monitor_application
        ;;
    *)
        echo "Usage: $0 {check|wait|fix|monitor}"
        echo ""
        echo "Commands:"
        echo "  check   - Perform a single health check (default)"
        echo "  wait    - Wait for application to become available"
        echo "  fix     - Attempt to fix application issues"
        echo "  monitor - Continuous monitoring with auto-recovery"
        echo ""
        echo "Environment variables:"
        echo "  CHECK_INTERVAL - Seconds between checks (default: 30)"
        echo "  MAX_RETRIES    - Maximum retry attempts (default: 5)"
        echo "  RETRY_DELAY    - Seconds between retries (default: 10)"
        echo "  AWS_REGION     - AWS region (default: us-east-1)"
        exit 1
        ;;
esac
