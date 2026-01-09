#!/bin/bash
set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
TERRAFORM_DIR="$PROJECT_DIR/terraform"
APP_DIR="$PROJECT_DIR/application"
AWS_REGION="${AWS_REGION:-us-east-1}"

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║         Book Library - Deployment Script                    ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Function to print status
print_status() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_info() {
    echo -e "${BLUE}[i]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    echo -e "\n${BLUE}Checking prerequisites...${NC}\n"

    # Check Terraform
    if command -v terraform &> /dev/null; then
        print_status "Terraform is installed: $(terraform --version | head -1)"
    else
        print_error "Terraform is not installed"
        exit 1
    fi

    # Check AWS CLI
    if command -v aws &> /dev/null; then
        print_status "AWS CLI is installed: $(aws --version)"
    else
        print_error "AWS CLI is not installed"
        exit 1
    fi

    # Check AWS credentials
    if aws sts get-caller-identity &> /dev/null; then
        ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
        print_status "AWS credentials configured (Account: $ACCOUNT_ID)"
    else
        print_error "AWS credentials not configured"
        print_info "Run 'aws configure' to set up your credentials"
        exit 1
    fi

    # Check zip command
    if command -v zip &> /dev/null; then
        print_status "zip command available"
    else
        print_warning "zip command not found, installing..."
        apt-get update && apt-get install -y zip
    fi
}

# Initialize Terraform
init_terraform() {
    echo -e "\n${BLUE}Initializing Terraform...${NC}\n"

    cd "$TERRAFORM_DIR"
    terraform init -upgrade

    print_status "Terraform initialized successfully"
}

# Plan Terraform changes
plan_terraform() {
    echo -e "\n${BLUE}Planning infrastructure changes...${NC}\n"

    cd "$TERRAFORM_DIR"
    terraform plan -out=tfplan

    print_status "Terraform plan created"
}

# Apply Terraform
apply_terraform() {
    echo -e "\n${BLUE}Applying infrastructure changes...${NC}\n"

    cd "$TERRAFORM_DIR"

    if [ -f tfplan ]; then
        terraform apply tfplan
    else
        terraform apply -auto-approve
    fi

    print_status "Infrastructure deployed successfully"
}

# Package application
package_application() {
    echo -e "\n${BLUE}Packaging application...${NC}\n"

    cd "$APP_DIR"

    # Remove old package if exists
    rm -f application.zip

    # Create zip package
    zip -r application.zip . -x "*.pyc" -x "__pycache__/*" -x ".git/*" -x "*.zip"

    print_status "Application packaged: application.zip"
}

# Upload to S3
upload_to_s3() {
    echo -e "\n${BLUE}Uploading application to S3...${NC}\n"

    cd "$TERRAFORM_DIR"

    # Get S3 bucket name from Terraform output
    S3_BUCKET=$(terraform output -raw s3_app_bucket 2>/dev/null || echo "")

    if [ -z "$S3_BUCKET" ]; then
        print_error "Could not get S3 bucket name from Terraform outputs"
        print_info "Make sure infrastructure is deployed first"
        exit 1
    fi

    print_info "Uploading to bucket: $S3_BUCKET"

    aws s3 cp "$APP_DIR/application.zip" "s3://$S3_BUCKET/application.zip" --region "$AWS_REGION"

    print_status "Application uploaded to S3"
}

# Trigger EC2 update
update_ec2() {
    echo -e "\n${BLUE}Updating EC2 instance...${NC}\n"

    cd "$TERRAFORM_DIR"

    INSTANCE_ID=$(terraform output -raw instance_id 2>/dev/null || echo "")
    S3_BUCKET=$(terraform output -raw s3_app_bucket 2>/dev/null || echo "")

    if [ -z "$INSTANCE_ID" ]; then
        print_error "Could not get EC2 instance ID"
        exit 1
    fi

    print_info "Connecting to instance: $INSTANCE_ID"

    # Use SSM to run commands on the instance
    COMMAND_ID=$(aws ssm send-command \
        --instance-ids "$INSTANCE_ID" \
        --document-name "AWS-RunShellScript" \
        --parameters commands=["cd /opt/book-library && aws s3 cp s3://$S3_BUCKET/application.zip . && unzip -o application.zip && systemctl restart book-library"] \
        --region "$AWS_REGION" \
        --query 'Command.CommandId' \
        --output text 2>/dev/null || echo "")

    if [ -n "$COMMAND_ID" ]; then
        print_info "SSM Command sent: $COMMAND_ID"

        # Wait for command to complete
        sleep 10
        aws ssm get-command-invocation \
            --command-id "$COMMAND_ID" \
            --instance-id "$INSTANCE_ID" \
            --region "$AWS_REGION" 2>/dev/null || true

        print_status "EC2 instance updated"
    else
        print_warning "SSM command failed, trying SSH..."

        # Get private key path and public IP
        KEY_PATH=$(terraform output -raw private_key_path 2>/dev/null || echo "")
        PUBLIC_IP=$(terraform output -raw instance_public_ip 2>/dev/null || echo "")

        if [ -n "$KEY_PATH" ] && [ -n "$PUBLIC_IP" ]; then
            print_info "Connecting via SSH to $PUBLIC_IP"

            ssh -i "$KEY_PATH" -o StrictHostKeyChecking=no ec2-user@"$PUBLIC_IP" << ENDSSH
                cd /opt/book-library
                aws s3 cp s3://$S3_BUCKET/application.zip . --region $AWS_REGION
                unzip -o application.zip
                sudo systemctl restart book-library
ENDSSH

            print_status "EC2 instance updated via SSH"
        else
            print_warning "Manual update may be required"
        fi
    fi
}

# Get deployment info
show_deployment_info() {
    echo -e "\n${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}        Deployment Complete! 🎉${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}\n"

    cd "$TERRAFORM_DIR"

    APP_URL=$(terraform output -raw app_url 2>/dev/null || echo "N/A")
    PUBLIC_IP=$(terraform output -raw instance_public_ip 2>/dev/null || echo "N/A")
    SSH_CMD=$(terraform output -raw ssh_command 2>/dev/null || echo "N/A")

    echo -e "  ${GREEN}Application URL:${NC}  $APP_URL"
    echo -e "  ${GREEN}Public IP:${NC}        $PUBLIC_IP"
    echo -e "  ${GREEN}SSH Command:${NC}      $SSH_CMD"
    echo ""
    echo -e "${YELLOW}Note: It may take 1-2 minutes for the application to be fully available.${NC}"
    echo ""
}

# Main deployment flow
main() {
    case "${1:-full}" in
        check)
            check_prerequisites
            ;;
        init)
            check_prerequisites
            init_terraform
            ;;
        plan)
            check_prerequisites
            init_terraform
            plan_terraform
            ;;
        infra)
            check_prerequisites
            init_terraform
            apply_terraform
            show_deployment_info
            ;;
        app)
            check_prerequisites
            package_application
            upload_to_s3
            update_ec2
            show_deployment_info
            ;;
        full)
            check_prerequisites
            init_terraform
            apply_terraform
            package_application
            upload_to_s3
            sleep 30  # Wait for EC2 to be ready
            update_ec2
            show_deployment_info
            ;;
        info)
            show_deployment_info
            ;;
        *)
            echo "Usage: $0 {check|init|plan|infra|app|full|info}"
            echo ""
            echo "Commands:"
            echo "  check  - Check prerequisites"
            echo "  init   - Initialize Terraform"
            echo "  plan   - Plan infrastructure changes"
            echo "  infra  - Deploy infrastructure only"
            echo "  app    - Deploy application only"
            echo "  full   - Full deployment (default)"
            echo "  info   - Show deployment information"
            exit 1
            ;;
    esac
}

main "$@"
